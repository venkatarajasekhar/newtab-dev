#!/usr/bin/perl5
#############################################################################
# $Id: psoftsync.pl,v 1.3 1998/08/13 09:11:50 leif Exp $
#
# The contents of this file are subject to the Mozilla Public License
# Version 1.0 (the "License"); you may not use this file except in
# compliance with the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS"
# basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
# License for the specific language governing rights and limitations
# under the License.
#
# The Original Code is PerLDAP. The Initial Developer of the Original
# Code is Netscape Communications Corp. and Clayton Donley. Portions
# created by Netscape are Copyright (C) Netscape Communications
# Corp., portions created by Clayton Donley are Copyright (C) Clayton
# Donley. All Rights Reserved.
#
# Contributor(s):
#
# DESCRIPTION
#    Synchronise some LDAP info with a PeopleSoft "dump". This "dump" file
#    is a "tab" separated file, as generated by an SQL utility on the
#    Oracle server.
#
#############################################################################

use Getopt::Std;			# To parse command line arguments.
use Mozilla::LDAP::Conn;		# Main "OO" layer for LDAP
use Mozilla::LDAP::Utils;		# LULU, utilities.


#############################################################################
# Local configurations, check these out . Note that SYNCS and ORDER has to
# have the same fields, this is because the hash array doesn't preserve
# the order of it's entries... :-( The "codes" are bit fields, where the
# three LSB are used as
#
#	 1  Force the update, even if attribute is empty (i.e. delete it)
#	 2  The attribute is the base for a DN (e.g. "manager").
#	 4  The attribute should be deleted if the user is not in PeopleSoft.
#	 8  Don't warn if the attribute is missing in the Psoft file (-W option).
#	16  Always delete this attribute in the PeopleSoft entry.
#	32  Delete this attribute if the account has "expired".
#
%SYNCS = (
	  "nscpharold" => 1 + 4,
	  "uid" => 0,
	  "" => 0,
	  "" => 0,
	  "employeenumber" => 1 + 4 + 32,
	  "departmentnumber" => 1 + 4,
	  "" => 0,
	  "" => 0,
	  "" => 0,
	  "manager" => 1 + 2,
	  "title" => 1 + 4 + 16 + 32,
	  "ou" =>  1 + 4 + 32,
	  "businesscategory" => 1 + 4 + 32,
	  "employeetype" => 0,
	  "nscppersonexpdate" => 1 + 8
	  );

@ORDER = (
	  "nscpharold",
	  "uid",
	  "",
	  "",
	  "employeenumber",
	  "departmentnumber",
	  "",
	  "",
	  "",
	  "manager",
	  "title",
	  "ou",
	  "businesscategory",
	  "employeetype",
	  "nscppersonexpdate"
	  );

# This is used for mapping the employeeType attribute into a readable format.
%EMPCODES = (
	     "A" => "Applicant",
	     "C" => "Contractor",
	     "E" => "Employee",
	     "O" => "OEM Partner",
	     "T" => "Interim",
	     "V" => "Vendor"
	     );

# Expiration policy for other attributes, the EXPDELAY is a convenience
# default setting.
$EXPDELAY = 24 * 7;
%EXPIRES = (
	    "carlicense"		=> $EXPDELAY,
	    "mailautoreplymode"		=> $EXPDELAY,
	    "mailautoreplytext"		=> $EXPDELAY,
	    "mailforwardingaddress"	=> $EXPDELAY,
	    "facsimiletelephonenumber"	=> $EXPDELAY
	    );
	    

$NOTYPE = "Unknown";
$DELIMITER = "%%";
$SENDMAIL = "/usr/lib/sendmail";

$SEARCH = "(&(uid=*)(!(objectclass=pseudoAccount)))";
$MAILTO = "leif\@netscape.com";

#$LDAP_DEBUG = 1;


#############################################################################
# Constants, shouldn't have to edit these...
#
$APPNAM	= "psoftsync";
$USAGE	= "$APPNAM [-nvW] -b base -h host -D bind -w passwd -P cert PS_file";

@ATTRIBUTES = uniq(@ORDER);
push(@ATTRIBUTES, "objectclass");

$TODAY = `/usr/bin/date '+%Y%m%d'`;
chop($TODAY);


#############################################################################
# Print an error for the PeopleSoft data. Note that we use the "__XXX__" fields
# here, to avoid the problem when an attribute is "expired" or modified.
#
sub psoftError
{
  my($str, $entry) = @_;

  print "Error: $str: ";
  print $entry->key(), " (";
  print $entry->{__employeenumber__}, ", ";
  print $entry->{__employeetype__}, ", ";
  print $entry->{__departmentnumber__}, ")\n";
}


#############################################################################
# Read in a PeopleSoft file, and create all the entries.
#
sub readDump
{
  my($file) = @_;
  my(@info);
  my(%entries);
  my($val);

  if (!open(PSOFT, $file))
    {
      print "Error: Can't read file $file\n";

      exit(1);
    }

  while (<PSOFT>)
    {
      next unless /$DELIMITER/;

      @info = split(/\s*%%\s*/);
      $entry = new PsoftEntry($info[$[]);
      foreach $attr (@ORDER)
	{
	  $val = shift(@info);
	  next if ($attr eq "");

	  $entry->add($attr, $val, $SYNCS{$attr});
	}
      #
      # Perhaps we should do some sanity checks here on the PeopleSoft data?
      #

      # Clean up some data if the user has expired ("best before...")
      if ($entry->expired($entry->{nscppersonexpdate}))
	{
	  foreach $attr (@ORDER)
	    {
	      next unless $attr;

	      delete($entry->{$attr}) if ($SYNCS{$attr} & 32);
	    }
	}

      if ($entry->{uid})
	{
	  $entries{$entry->{uid}} = $entry;
	}
      elsif ($opt_W)
	{
	  psoftError("No UID", $entry);
	}
    }
  close(PSOFT);

  return %entries;
}


#############################################################################
# Make a list "uniq", just like the Unix command.
#
sub uniq {				# uniq(elements[])
   my(%tmp);
   
   grep($tmp{$_}++, @_);
   return sort(keys(%tmp));
}


#############################################################################
# Delete an attribute from an entry.
#
sub delAttr {				# delAttr(ENTRY, ATTR)
  ($entry, $attr) = @_;

  if (defined($entry->{$attr}))
    {
      $out->write("Deleted $attr for user: $entry->{uid}[0]") if $opt_v;
      delete($entry->{$attr});

      return 1;
    }

  return 0;
}


#############################################################################
# Check arguments, and configure some parameters accordingly..
#
if (!getopts('nvMWb:h:D:p:s:w:P:'))
{
  print "usage: $APPNAM $USAGE\n";
  exit;
}
%ld = Mozilla::LDAP::Utils::ldapArgs();
Mozilla::LDAP::Utils::userCredentials(\%ld) unless $opt_n;

$out = new Mail();
if ($opt_M)
{
  $out->set("to", $MAILTO);
  $out->set("subject", "Hoth: PeopleSoft synchronization report");
}
else
{
  $out->echo();
  $out->nomail();
}


#############################################################################
# Read in all the PeopleSoft entries, and then instantiate an LDAP object,
# which also binds to the LDAP server.
#
%psoft = readDump(@ARGV[$[]);
$conn = new Mozilla::LDAP::Conn(\%ld);
die "Could't connect to LDAP server $ld{host}" unless $conn;


#############################################################################
# Now process all the users, one by one.
#
$entry = $conn->search($ld{root}, "subtree", $SEARCH, 0, @ATTRIBUTES);

while ($entry)
{
  $uid = $entry->{"uid"}[0];
  $changed = 0;

  $psent = $psoft{$uid};
  if (!$psent)
    {
      print "Error: LDAP user $uid: No entry in PeopleSoft\n" if $opt_W;
      foreach $attr (@ORDER)
	{
	  next unless $attr;
	  $changed += delAttr($entry, $attr) if ($SYNCS{$attr} & 4);
	}
      if ($entry->{employeetype}[0] ne "$NOTYPE")
	{
	  $entry->{employeetype} = ["$NOTYPE"];
	  $changed = 1;
	  $out->write("Set employeeType to $NOTYPE for user: $uid") if $opt_v;
	}
	  
    }
  else
    {
      $psent->handled(1);
      foreach $attr (@ORDER)
	{
	  next unless $attr;

	  if (!defined($psent->{$attr}) || ($psent->{$attr} eq ""))
	    {
	      $changed += delAttr($entry, $attr) if ($SYNCS{$attr} & 1);
	    }
	  elsif ($entry->{$attr}[0] ne $psent->{$attr})
	    {
	      $entry->{$attr} = [$psent->{$attr}];
	      $changed = 1;
	      $out->write("Set $attr to $psent->{$attr} for user: $uid") if $opt_v;
	    }
	}
      # Now handle the Expire date special case...
      if ($psent->expired() ne "")
	{
	  if ($entry->addValue("objectclass", "nscphidethis"))
	    {
	      $changed = 1;
	      $out->write("Expiring the user: $uid") if $opt_v;
	    }

	  # Expire other attributes, IFF the expire is over a certain
	  # treshhold (e.g. a week).
	}
      elsif ($entry->removeValue("objectclass", "nscphidethis"))
	{
	  $changed = 1;
	  $out->write("Enabling the user: $uid") if $opt_v;
	}
    }

  $conn->update($entry) if ($changed && ! $opt_n);
  $entry = $conn->entry();
}


#############################################################################
# Close the LDAP connection.
#
$conn->close if $conn;


#############################################################################
# Post process, figure out which PSoft entries have no entry in LDAP.
#
if ($opt_W)
{
  foreach (keys(%psoft))
    {
      $ent=$psoft{$_};
      
      psoftError("No LDAP entry", $ent) unless $ent->handled();
    }
}



#############################################################################
# Package to an entry from the PeopleSoft database.
#
package PsoftEntry;


#############################################################################
# Creator.
#
sub new
{
  my($class, $key) = @_;
  my $self = {};
  
  bless $self, ref $class || $class;
  $self->{__key__} = $key;

  return $self;
}


#############################################################################
# Add an attribute/field to the entry.
#
sub add
{
  my($self, $attr, $val, $lev) = @_;

  return if ($lev & 16);

  $attr = lc $attr;
  if ($attr eq "employeetype")
    {
      if (defined($main::EMPCODES{$val}))
	{
	  $self->{$attr} = $main::EMPCODES{$val};
	}
      else
	{
	  $self->{$attr} = $main::NOTYPE;
	}
      $self->{__employeetype__} = $val;
    }
  elsif ($val eq "")
    {
      main::psoftError("No attribute $attr", $self)
	if ($main::opt_W && ($lev & 1) && !($lev & 8));
    }
  else
    {
      $self->{$attr} = ($lev & 2) ? "uid=$val,$main::ld{root}" : $val;
      $self->{"__${attr}__"} = $val;
    }
}


#############################################################################
# Return the value for an attribute/field.
#
sub get
{
  my($self, $attr) = @_;

  return $self->{$attr};
}


#############################################################################
# Mark the entry as "expired". If there is no "date" argument, we'll return
# the current entries expire status.
#
sub expired
{
  my($self, $date) = @_;

  if ($date)
    {
      # Only expire entries with reasonable expire dates...
      if (length($date) != 8)
	{
	  main::psoftError("Bad expire date", $self) if $main::opt_W;

	  return 0;
	}

      if ($date lt $main::TODAY)
	{
	  $self->{employeetype} = "$NOTYPE";
	  $self->{__expired__} = 1;

	  return 1;
	}
    }

  return $self->{__expired__};
}


#############################################################################
# Mark the entry as "handled", i.e. it exists in LDAP.
#
sub handled
{
  my($self, $flag) = @_;

  $self->{__handled__} = 1 if $flag;

  return $self->{__handled__};
}


#############################################################################
# Return the "key" of this entry, typically the name field.
#
sub key
{
  my($self) = @_;

  return $self->{__key__};
}


#################################################################################
# This sub-package will send mail to some recipients, IFF there is anything to
# send, or your force it to send. Note that the Subject doesn't qualify it to
# send a message (force it to send if you have to).
#
package Mail;


#################################################################################
# The constructor, which optionally takes the TO, FROM and SUBJECT.
#
sub new
{
  my($class, $to, $from, $subject) = @_;
  my $self = {};

  bless $self, ref $class || $class;

  $self->{to} = $to || "root";
  $self->{from} = $from || "ldap";
  $self->{subject} = $subject || "Output from LDAP script\n";
  @{$self->{message}} = ();
  $self->{send} = 0;
  $self->{nomail} = 0;
  $self->{echo} = 0;

  return $self;
}


#################################################################################
# Destructor, which will also send the message, if appropriate.
#
sub DESTROY
{
  my($self) = @_;

  if ($self->{send} && !$self->{nomail})
    {
      $self->send();
      $self->{send} = 0;
    }
}


#################################################################################
# Set a field for this entry, e.g. From:, To: etc.
#
sub set
{
  my($self, $field, $string) = @_;

  if ($field && $string)
    {
      $field = lc $field;
      $self->{$field} = $string;
    }
}


#################################################################################
# Add a line to the message, the argument is the string.
#
sub write
{
  my($self, $string) = @_;

  if ($string ne "")
    {
      push(@{$self->{message}}, $string);
      print "$string\n" if $self->{echo};

      $self->{send}++;
    }
}


#################################################################################
# Force the object to send the message, no matter if there's anything in the
# body or not.
#
sub force
{
  my($self) = @_;

  $self->{send} = 1;
  $self->{nomail} = 0;
}


#################################################################################
# Don't send the mail, this is the oppositte to "force...
#
sub nomail
{
  my($self) = @_;

  $self->{send} = 0;
  $self->{nomail} = 1;
}


#################################################################################
# Enable echo-mode, where we will also print everything to STDOUT.
#
sub echo
{
  my($self) = @_;

  $self->{echo} = 1;
}


#################################################################################
# Actually send the message. This is automatically done by the DESTROY method,
# but we can force it to do it this way.
#
sub send
{
  my($self) = @_;

  if ($self->{send} && !$self->{nomail})
    {
      open(MAILER, "|$main::SENDMAIL -t");
      print MAILER "From: $self->{from}\n";
      print MAILER "To: $self->{to}\n";
      print MAILER "Subject: $self->{subject}\n\n";

      foreach (@{$self->{message}})
	{
	  print MAILER "$_\n";
	}
      print MAILER ".\n";

      close(MAILER);
      $self->{send} = 0;
    }
}
