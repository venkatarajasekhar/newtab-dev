// PrintProgressDialog.cpp : implementation file
//

#include "stdafx.h"
#include "Testembed.h"
#include "PrintProgressDialog.h"
#include "BrowserView.h"
#include "nsIWebBrowser.h"
#include "nsIWebBrowserPrint.h"
#include "nsIWebProgressListener.h"

#ifdef _DEBUG
#define new DEBUG_NEW
#undef THIS_FILE
static char THIS_FILE[] = __FILE__;
#endif

/////////////////////////////////////////////////////////////////////////////
// CPrintProgressDialog dialog

class CDlgPrintListener : public nsIWebProgressListener
{
// Construction
public:
	CDlgPrintListener(CPrintProgressDialog* aDlg); 

  NS_DECL_ISUPPORTS
  NS_DECL_NSIWEBPROGRESSLISTENER


  void ClearDlg() { m_PrintDlg = NULL; } // weak reference

// Implementation
protected:
	CPrintProgressDialog* m_PrintDlg;
};

NS_IMPL_ADDREF(CDlgPrintListener)
NS_IMPL_RELEASE(CDlgPrintListener)

NS_INTERFACE_MAP_BEGIN(CDlgPrintListener)
    NS_INTERFACE_MAP_ENTRY_AMBIGUOUS(nsISupports, nsIWebProgressListener)
    NS_INTERFACE_MAP_ENTRY(nsIWebProgressListener)
NS_INTERFACE_MAP_END


CDlgPrintListener::CDlgPrintListener(CPrintProgressDialog* aDlg) :
  m_PrintDlg(aDlg)
{
  NS_INIT_ISUPPORTS();
  //NS_ADDREF_THIS();
}

/* void onStateChange (in nsIWebProgress aWebProgress, in nsIRequest aRequest, in long aStateFlags, in unsigned long aStatus); */
NS_IMETHODIMP 
CDlgPrintListener::OnStateChange(nsIWebProgress *aWebProgress, nsIRequest *aRequest, PRInt32 aStateFlags, PRUint32 aStatus)
{
  if (m_PrintDlg) {
    if (aStatus == nsIWebProgressListener::STATE_START) {
      return m_PrintDlg->OnStartPrinting();

    } else if (aStatus == nsIWebProgressListener::STATE_STOP) {
      return m_PrintDlg->OnEndPrinting(aStatus);
    }
  }
  return NS_OK;
}

/* void onProgressChange (in nsIWebProgress aWebProgress, in nsIRequest aRequest, in long aCurSelfProgress, in long aMaxSelfProgress, in long aCurTotalProgress, in long aMaxTotalProgress); */
NS_IMETHODIMP 
CDlgPrintListener::OnProgressChange(nsIWebProgress *aWebProgress, nsIRequest *aRequest, PRInt32 aCurSelfProgress, PRInt32 aMaxSelfProgress, PRInt32 aCurTotalProgress, PRInt32 aMaxTotalProgress)
{
  if (m_PrintDlg) {
    return m_PrintDlg->OnProgressPrinting(aCurSelfProgress, aMaxSelfProgress);
  }
  return NS_OK;
}

/* void onLocationChange (in nsIWebProgress aWebProgress, in nsIRequest aRequest, in nsIURI location); */
NS_IMETHODIMP 
CDlgPrintListener::OnLocationChange(nsIWebProgress *aWebProgress, nsIRequest *aRequest, nsIURI *location)
{
    return NS_ERROR_NOT_IMPLEMENTED;
}

/* void onStatusChange (in nsIWebProgress aWebProgress, in nsIRequest aRequest, in nsresult aStatus, in wstring aMessage); */
NS_IMETHODIMP 
CDlgPrintListener::OnStatusChange(nsIWebProgress *aWebProgress, nsIRequest *aRequest, nsresult aStatus, const PRUnichar *aMessage)
{
    return NS_ERROR_NOT_IMPLEMENTED;
}

/* void onSecurityChange (in nsIWebProgress aWebProgress, in nsIRequest aRequest, in long state); */
NS_IMETHODIMP 
CDlgPrintListener::OnSecurityChange(nsIWebProgress *aWebProgress, nsIRequest *aRequest, PRInt32 state)
{
    return NS_ERROR_NOT_IMPLEMENTED;
}

/////////////////////////////////////////////////////////////////////////////
// CPrintProgressDialog dialog


CPrintProgressDialog::CPrintProgressDialog(nsIWebBrowser* aWebBrowser,
                                           nsIDOMWindow* aDOMWin,
                                           CWnd* pParent /*=NULL*/)
	: CDialog(CPrintProgressDialog::IDD, pParent),
  m_WebBrowser(aWebBrowser),
  m_DOMWin(aDOMWin),
  m_PrintListener(nsnull),
  m_InModalMode(PR_FALSE)
{
	//{{AFX_DATA_INIT(CPrintProgressDialog)
		// NOTE: the ClassWizard will add member initialization here
	//}}AFX_DATA_INIT
}

CPrintProgressDialog::~CPrintProgressDialog()
{
  CDlgPrintListener * pl = (CDlgPrintListener*)m_PrintListener.get();
  if (pl) {
    pl->ClearDlg();
  }
}


void CPrintProgressDialog::DoDataExchange(CDataExchange* pDX)
{
	CDialog::DoDataExchange(pDX);
	//{{AFX_DATA_MAP(CPrintProgressDialog)
		// NOTE: the ClassWizard will add DDX and DDV calls here
	//}}AFX_DATA_MAP
}


BEGIN_MESSAGE_MAP(CPrintProgressDialog, CDialog)
	//{{AFX_MSG_MAP(CPrintProgressDialog)
	//}}AFX_MSG_MAP
END_MESSAGE_MAP()

/////////////////////////////////////////////////////////////////////////////
// CPrintProgressDialog message handlers
static void GetLocalRect(CWnd * aWnd, CRect& aRect, CWnd * aParent)
{
  CRect wr;
  aParent->GetWindowRect(wr);

  CRect cr;
  aParent->GetClientRect(cr);

  aWnd->GetWindowRect(aRect);

  int borderH = wr.Height() - cr.Height();
  int borderW = (wr.Width() - cr.Width())/2;
  aRect.top    -= wr.top+borderH-borderW;
  aRect.left   -= wr.left+borderW;
  aRect.right  -= wr.left+borderW;
  aRect.bottom -= wr.top+borderH-borderW;

}

BOOL CPrintProgressDialog::OnInitDialog() 
{
	CDialog::OnInitDialog();
	
	CRect clientRect;
	GetClientRect(&clientRect);

	CRect titleRect;
  GetLocalRect(GetDlgItem(IDC_PPD_DOC_TITLE_STATIC), titleRect, this);

	CRect itemRect;
  GetLocalRect(GetDlgItem(IDC_PPD_DOC_TXT), itemRect, this);

  CRect progRect;
  progRect.left   = titleRect.left;
  progRect.top    = itemRect.top+itemRect.Height()+5;
  progRect.right  = clientRect.Width()-(2*titleRect.left);
  progRect.bottom = progRect.top+titleRect.Height();


	m_wndProgress.Create (WS_CHILD | WS_VISIBLE, progRect, this, -1);
	m_wndProgress.SetPos (0);
	
	return TRUE;  // return TRUE unless you set the focus to a control
	              // EXCEPTION: OCX Property Pages should return FALSE
}


int CPrintProgressDialog::DoModal( )
{
  PRBool doModal = PR_FALSE;
	nsCOMPtr<nsIWebBrowserPrint> print(do_GetInterface(m_WebBrowser));
  if(print) 
  {
    m_PrintListener = new CDlgPrintListener(this); // constructor addrefs
    if (m_PrintListener) {
      // doModal will be set to false if the print job was cancelled
      doModal = NS_SUCCEEDED(print->Print(m_DOMWin, nsnull, nsnull)) == PR_TRUE;
    }
  }

  if (doModal) {
    m_InModalMode = PR_TRUE;
    return CDialog::DoModal();
  }
  return 0;
}


void CPrintProgressDialog::OnCancel() 
{
  nsCOMPtr<nsIWebBrowserPrint> print(do_GetInterface(m_WebBrowser));
  if (print) {
    print->Cancel();
  }

	CDialog::OnCancel();
}

void CPrintProgressDialog::SetURI(const char* aTitle)
{
  m_URL = _T(aTitle);
}
