/* -*- Mode: C++; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 2 -*-
 *
 * The contents of this file are subject to the Mozilla Public
 * License Version 1.1 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy of
 * the License at http://www.mozilla.org/MPL/
 * 
 * Software distributed under the License is distributed on an "AS
 * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * rights and limitations under the License.
 * 
 * The Original Code is the Mozilla browser.
 * 
 * The Initial Developer of the Original Code is Netscape
 * Communications, Inc.  Portions created by Netscape are
 * Copyright (C) 1999, Mozilla.  All Rights Reserved.
 * 
 * Contributor(s):
 *   Adam Lock <adamlock@netscape.com>
 */

#include "nsCommandHandler.h"
#include "nsWebBrowser.h"
#include "nsDocShellTreeOwner.h"

#include "nsIScriptGlobalObject.h"

nsCommandHandler::nsCommandHandler() :
    mWindow(nsnull)
{
    NS_INIT_REFCNT();
}

nsCommandHandler::~nsCommandHandler()
{
}

nsresult nsCommandHandler::GetCommandHandler(nsICommandHandler **aCommandHandler)
{
    NS_ENSURE_ARG_POINTER(aCommandHandler);

    *aCommandHandler = nsnull;
    if (mWindow == nsnull)
    {
        return NS_ERROR_FAILURE;
    }

    nsCOMPtr<nsIScriptGlobalObject> globalObj( do_QueryInterface(mWindow) );
    if (!globalObj)
    {
        return NS_ERROR_FAILURE;
    }

    nsCOMPtr<nsIDocShell> docShell;
    globalObj->GetDocShell(getter_AddRefs(docShell));

    // Find the treeowner
    nsCOMPtr<nsIDocShellTreeItem> docShellAsTreeItem(do_QueryInterface(docShell));
    nsIWebBrowser *webBrowser = nsnull;

    nsIDocShellTreeOwner *treeOwner = nsnull;
    docShellAsTreeItem->GetTreeOwner(&treeOwner);
    
    // See if the client on the tree owner implements nsICommandHandler
    if (treeOwner)
    {
        nsDocShellTreeOwner *tree = NS_STATIC_CAST(nsDocShellTreeOwner *, treeOwner);
        if (tree->mTreeOwner)
        {
            nsresult rv;
            rv = tree->mTreeOwner->QueryInterface(NS_GET_IID(nsICommandHandler), (void **)aCommandHandler);
            NS_RELEASE(treeOwner);
            return rv;
        }
        NS_RELEASE(treeOwner);
     }
    *aCommandHandler = nsnull;

    return NS_OK;
}

NS_IMPL_ADDREF(nsCommandHandler)
NS_IMPL_RELEASE(nsCommandHandler)

NS_INTERFACE_MAP_BEGIN(nsCommandHandler)
    NS_INTERFACE_MAP_ENTRY_AMBIGUOUS(nsISupports, nsICommandHandler)
    NS_INTERFACE_MAP_ENTRY(nsICommandHandlerInit)
    NS_INTERFACE_MAP_ENTRY(nsICommandHandler)
NS_INTERFACE_MAP_END

///////////////////////////////////////////////////////////////////////////////
// nsICommandHandlerInit implementation

/* attribute nsIDocShell docShell; */
NS_IMETHODIMP nsCommandHandler::GetWindow(nsIDOMWindow * *aWindow)
{
    *aWindow = nsnull;
    return NS_OK;
}

NS_IMETHODIMP nsCommandHandler::SetWindow(nsIDOMWindow * aWindow)
{
    if (aWindow == nsnull)
    {
       return NS_ERROR_FAILURE;
    }
    mWindow = aWindow;
    return NS_OK;
}

///////////////////////////////////////////////////////////////////////////////
// nsICommandHandler implementation

/* void do (in string aCommand, in string aStatus); */
NS_IMETHODIMP nsCommandHandler::Exec(const char *aCommand, const char *aStatus)
{
    nsCOMPtr<nsICommandHandler> commandHandler;
    GetCommandHandler(getter_AddRefs(commandHandler));

    if (commandHandler)
    {
        return commandHandler->Exec(aCommand, aStatus);
    }

    return NS_OK;
}

/* void query (in string aCommand, in string aStatus); */
NS_IMETHODIMP nsCommandHandler::Query(const char *aCommand, const char *aStatus)
{
    nsCOMPtr<nsICommandHandler> commandHandler;
    GetCommandHandler(getter_AddRefs(commandHandler));

    if (commandHandler)
    {
        return commandHandler->Query(aCommand, aStatus);
    }

    return NS_OK;
}
