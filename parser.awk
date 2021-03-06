#!/usr/bin/awk -f
################################################################################
# parser.awk - parsing script for awkiawki
# $Id: parser.awk,v 1.6 2002/12/07 13:46:45 olt Exp $
################################################################################
# Copyright (c) 2002 Oliver Tonnhofer (olt@bogosoft.com)
# See the file `COPYING' for copyright notice.
################################################################################
# GPL 12/2/1
# This goes through the entire body of the html page and parses wiki markup
# into html tags.

BEGIN {
	# list[] tracks the level of nesting for our list
	#   "ol" is for ordered (numbered) lists, 
	#   "ul" is for unordered (bulleted) lists--
	#   so if list["ol"] is 2, we are nested two deep.
	list["ol"] = 0
	list["ul"] = 0
	scriptname = ENVIRON["SCRIPT_NAME"]
	FS = "[ ]"
	
	cmd = "ls " datadir
	while ((cmd | getline ls_out) >0)
		if (match(ls_out, /[A-Z][a-z]+[A-Z][A-Za-z]*/) && substr(ls_out, RSTART + RLENGTH) !~ /,v/) {
			page = substr(ls_out, RSTART, RLENGTH)
			pages[page] = 1
		}
	close(cmd)
}

# register blanklines
/^$/ { blankline = 1; next; } # wikiprint($0) }

##########################################################
# Convert HTML entities for <, > and & to their & codes, so the
# 	web browser converts them literally instead of trying to 
#	decode them as HTML sequences.
/[^,;][&<>]/ { gsub(/&/, "\\&amp;");	gsub(/</, "\\&lt;"); gsub(/>/, "\\&gt;"); wikiprint(); }
# If escaped, we WANT the browser to decode them as HTML sequences--
#  so do that-- for instance, to include an image, you can use
#      ,<img src="path/imagefile.jpg",>
# ,&iexcl; and the like behave oddly since the wiki editor translates them
/[,;][&<>]/ { gsub(/[,;]&/, ",,&");	gsub(/[,;]</, ",,<"); gsub(/[,;]>/, ",,>"); gsub(/,,/,""); wikiprint(); }
##########################################################

# 12/3/17 Update table of contents: Assume a semicolon preceded by whitespace
#	means we have a link to add to the TOC
# 12/19/17 Further update: if preceded by whitespace, must not be FOLLOWED by whitespace-- for example, bash functions often have list delimter " ; " standing alone.
# DEBUG /[ \t];[^ \t]|^;[^ \t]/ { print "TOC link found: " $0 > "/dev/stderr"; }
/[ \t];[^ \t]|^;[^ \t]/ { 	
		toc_add=$0 
		# update bookmark id-- we will put a link to it
		# in the toc, and insert it in the current link as well
		id_num++;
		# set gNeedsIdTag and id_string so later
		# 	processing of tag adds the ID.
		gNeedIdTag=1
		id_string=" id=\"toc" id_num "\""

		if (/^;[1-6][ ]/) {
			# a header
			headerLevel=substr($0,2,1)
			tocIndent="style=\"margin-left: "(headerLevel-2) "em;\""
		} else {
			headerLevel=0;
			tocIndent="style=\"margin-left: 2em;\""
		}
		# strip off the wiki tag
		gsub(/;[0-9_.\/=@*#-]*/,"",toc_add);

		# create link for this tag
		toc_add="<li class=\"tight\" " tocIndent "><a href=\"#toc" id_num "\" class=\"tight\">" substr(toc_add,1,25) "</a></li>"
		# DEBUG dprint(toc_add)
		toc=toc toc_add "\n"
}

# 12/3/17 rework so most markup is prefixed with 
#	1) a comma; or
#	2) a semicolon (if linked to the table of contents for the page)
# 12/17/17: made gsub less greedy for bold, italic, and underline by 
#	using [^,;]* instead of .*


# about the italic regex:
#	[,;]\/ matches the first and last wikitag, ",/" (or ";/")
#		Then, in the body (between wikitags):
#		1. [^,;][^\/]* will not match a / unless it is NOT
#			preceded by a , or ;
#		|       OR:
#		2. [^,;]*[^\/] will not match a , or ;, unless
#			followed by a non-slash
# So, body rule (1) will ensure "let's italicize ,/this,/ but not this
#	but ,/this again,/ works.
# italic is ,/ or ;/
/[,;]\//  { gsub(/[,;]\/([^,;][^\/]*|[^,;]*[^\/]*)[,;]\//, "<i" add_id() ">&</i>"); gsub(/[,;]\//,""); wikiprint(); }

# BOLD is ,+ or ;+
/[,;]\+/ { gsub(/[,;]\+([^,;][^\+]*|[^,;]*[^\+]*)[,;]\+/, "<b" add_id() ">&</b>"); gsub(/[,;]\+/,""); wikiprint(); }

# underline is ,_ or ;_
/[,;]_/  { gsub(/[,;]_([^,;][^_]*|[^,;]*[^_]*)[,;]_/, "<u" add_id() ">&</u>"); gsub(/[,;]_/,""); wikiprint(); }

# mono (code) type is ,. or ;.
/[,;]\./  { gsub(/[,;]\.([^,;][^\.]*|[^,;]*[^\.]*)[,;]\./, "<span class=\"mono_preformat\"" add_id() ">&</span>"); gsub(/[,;]\./,""); wikiprint(); }

# "classed" code is ," or ;"
#	check for the "classed" text terminator first; this delimiter is
#	,"<space>
/[,;]\" / { gsub(/[,;]\" /,"</span>\\&nbsp;"); wikiprint(); } # end a class block

# Now check for the start of the "classed" code block
#	this delimiter is 
#	,"CLASSNAME<space>
/[,;]\"/  { 
	#gsub(/[,;]\"([^,;][^" ]*|[^,; ]*[^" ]*) [,;]\"/, "<span class=\"&\"" add_id() ">"); 
	#close_tags("list","classed"); 
	#class_spantag_open = 1;  wikiprint(); 
	gsub(/[,;]\"([^,;][^" ]*|[^,; ]*[^" ]*) /, "<span class=\"&\"" add_id() ">"); 
	gsub(/[,;]\"/,""); 
	wikiprint();
}


# any markup below this heading block cannot be included in a heading, since
# the next at the end of the heading code will skip everything else.

#headings
/^[,;][1-6][ ]/ { headerLevel=substr($0,2,1); $0 = "<h" headerLevel id_string ">" substr($0, 4) "</h" headerLevel ">"; id_string=""; close_tags("","h"); wikiprint($0); next; }

# generate links
/[A-Z][a-z]+[A-Z][A-Za-z]*/ ||
/(https?|ftp|gopher|mailto|news):/ {
	tmpline = ""
	for(i=1;i<=NF;i++) {
		field = $i 
		# generate HTML img tag for .jpg,.jpeg,.gif,png URLs
		if (field ~ /https?:\/\/[^\t]*\.(jpg|jpeg|gif|png)/ \
			&& field !~ /https?:\/\/[^\t]*\.(jpg|jpeg|gif|png)''''''/) {
			sub(/https?:\/\/[^\t]*\.(jpg|jpeg|gif|png)/, "<img src=\"&\">",field)
		# links for mailto, news and http, ftp and gopher URLs
		}else if (field ~ /((https?|ftp|gopher):\/\/|(mailto|news):)[^\t]*/) {
			sub(/((https?|ftp|gopher):\/\/|(mailto|news):)[^\t]*[^.,?;:'")\t]/, "<a href=\"&\">&</a>",field)
			# remove mailto: in link description
			sub(/>mailto:/, ">",field)
		# links for awkipages
		}else if (field ~ /(^|[[,.?;:'"\(\t])[A-Z][a-z]+[A-Z][A-Za-z]*/ && field !~ /''''''/) {
			match(field, /[A-Z][a-z]+[A-Z][A-Za-z]*/)
			tmp_pagename = substr(field, RSTART, RLENGTH)
			if (pages[tmp_pagename])
				sub(/[A-Z][a-z]+[A-Z][A-Za-z]*/, "<a href=\""scriptname"/&\">&</a>",field)
			else
				sub(/[A-Z][a-z]+[A-Z][A-Za-z]*/, "&<a href=\""scriptname"/&\">?</a>",field)
		}
		tmpline = tmpline field OFS
	}
	# return tmpline to $0 and remove last OFS (whitespace)
	$0 = substr(tmpline, 1, length(tmpline)-1)
	# Why not wikiprint($0) here? Well, it adds it garbage--
	#	I don't know why...
	# wikiprint($0)
}

function add_id() {
		# does nothing unless a toc-id is needed,
		#	which we know know at this point because
		#	gNeedIdTag should be set if toc was updated.
		if (gNeedIdTag) {
			gNeedIdTag=0
			return id_string
		}
	}

function num_in_tag(sTag) {
	nPos=match($0,sTag)
	sNum=substr($0,nPos+1)
	nNum=sNum+0
	# DEBUG print "nPos=" nPos " sNum=" sNum " nNum=" nNum > "/dev/stderr"
	return sNum + 0
}

function dprint(sDebug) { 
	if (sDebug == "")
		print $0 > "/dev/stderr" ;
	else
		print sDebug > "/dev/stderr" ; }

# images are ,@ or ;@, with optional size (in width%) before the @
#	Example: ,50@path/image.png,@
/[,;][0-9]*@/ {	
	while (/[,;][0-9]*@/) {
		# as long as we keep finding the ,@ tag, keep going
		nPercent = num_in_tag("[,;][0-9]*@") 
		# default nPercent (if no number) is 100%
		if (nPercent == 0)
			nPercent = 100
		# sub our tag with <div> of correct max width,
		#	and image using 100% of div inside.
		sub(/[,;][0-9]*@(.*)[,;]@/,"<div style=\"max-width:" nPercent "%;\"" add_id() "><img src=\"" imagedir "&\" style=\"width: 100%;\"></div>");
		# We need to remove three tags-- the original
		#	start and end of image, and the
		#	one inserted with the filename when
		#	we used the &
		for (i=0; i<3; i++)
			sub(/[,;][0-9]*@/,"");
		# DEBUG dprint();
	}
	wikiprint();
}

# indents are ,= or ;= positive or negative fractional # can precede=
#	Example: ,2= is a double indent
/[,;][-.0-9]*=/ {	
	#DEBUG dprint("Start Line is " $0)
	# determine nIndent amount (can be negative, fractional)
	nIndent = num_in_tag("[,;][-.0-9]*=") 
	# default indent (if no number) is 1 
	if (nIndent == 0)
		nIndent = 1
	# sub our tag with <div> of correct margin
	sub(/[,;][-.0-9]*=/,"<div style=\"margin-left:" nIndent "em;\"" add_id() ">");
	# close the div at the end of the record.
	sub(/$/,"</div>")
	#DEBUG dprint("End Line is " $0)
	# don't close out a list
	no_close_list=1
	# don't add an extra line break at end of a div-- already handled by div
	no_break=1
}


#lists
/[,;]+\*/ { no_close_list=0; close_tags("list","*"); parse_list("ul", "ol"); wikiprint(); next;}
/[,;]+\#/ { close_tags("list","#"); parse_list("ol", "ul"); wikiprint(); next;}

# horizontal line
/^[,;]-/ { sub(/^[,;]-+/, "<hr" add_id() ">"); blankline = 1; close_tags("","-"); wikiprint($0); next; }

/^ / { 
	close_tags("pre","pre");
	if (pre != 1) {
		wikiprint( "<pre" add_id() ">" $0); pre = 1
		blankline = 0
	} else { 
		if (blankline==1) {
			# Don't use <br/> since pre takes care of blank lines itself 
			wikiprint();
			blankline = 0
		}
		wikiprint($0);
	}
	next;
}

NR == 1 { wikiprint( "<p>"); }

{
	if (no_close_list == 1) {
		close_tags("list","?")
		no_close_list = 0;
	}
	else
		close_tags("","?");
	
	# print paragraph when blankline registered
	if (blankline==1) {
		wikiprint("<p>");
		blankline=0;
	}

	#print line
	if (no_break == 0)
		wikiprint($0 "<br/>")
	else {
		wikiprint($0)
		no_break=0
	}
}

END {
	$0 = ""
	close_tags("","END");
#	wikiprint();
	tocprint()
	# DEBUG (duplicates that in wikiprint) print wikibody > "/dev/stderr"
	# NOTE: This file was invoked from awki.cgi using a "| getline"
 	# syntax, meaning that prints from here are NOT directly
	# sent to the web browser (they go to awki.cgi first).
	# To make text pretty for web inspectors, 
	# we need newlines in "wikibody" AND in awki.cgi.
	print wikibody "\n"
}
function tocprint()
{
	if (toc != "") {
		print "<div class=\"toc\">"
		print "<h3 class=\"tight\" style=\"margin-left: 5em\">Contents</h3>"
		print "<ul class=\"tight\">"
		print toc
		print "</ul class=\"tight\">"
		# links for top and bottom
		print "<a href=\"#top\">[Top]</a><a href=\"#bottom\" style=\"float: right;\">[Bottom]</a>"
		#
		print "</div>"
	}
}


function close_tags(dont_close,caller) {
	# dont_close: don't close whatever tag this is, close other tags.
	# caller: ONLY PURPOSE IS FOR USE DEBUGGING!
	# DEBUG print "close_tags(" dont_close"," caller")" >"/dev/stderr"
	# close monospace
#	if (class_spantag_open == 1) {
#		print "close_tags(" dont_close"," caller") *****************" >"/dev/stderr"
#		
#		wikiprint("</span>")
#		class_spantag_open = 0
#	}
	if (dont_close !~ "pre") {
		# if not isn't "pre" we get here--
		# so we get here for close_tags("list") 
		# a plain close_tags()
		if (pre == 1) {
			wikiprint("</pre>")
			pre = 0
		}
		# We don't close lists just because we started
		# a "pre" block or a "span" block-- so the "not list"
		# test goes here.
		#
		# if list is parsed this line print it
		if (dont_close !~ "list") {
			# if not isn't "list" we get here--
			# so we get here for close_tags("pre") or
			# a plain close_tags()
			if (list["ol"] > 0) {
				parse_list("ol", "ul")
			} else if (list["ul"] > 0) {
				parse_list("ul", "ol")
			} 
		}
	}
}
function update_toc() {
	#  updates table of contents when a ';' prefix is used.
}
function parse_list(this, other) {
	#    The wikimarkup for a list is
	# ,* First bullet item
        # ,* Next bullet item
   	#    OR, for a numbered list,
	# ,# first numbered item
        # ,# second numbered item
        #    and so on.
        # tabs can be used instead of tildas.
        # Lists can be nested in lists by prefixing more tabs or tildas. 
	# list[] variable tells level of the nest we are in.
        # this and other correspond to HTML tag: 
	#    ("ul" for unordered list, "ol" for ordered list)
	thislist = list[this]
	otherlist = list[other]
	tabcount = 0

	# As long as a markup prefix is present, remove it and increase tab (nesting) count
	while(/^[,;]+[#*]/) {
		sub(/^[,;]/,"")
		tabcount++
	}
	
	# close foreign tags-- end that list.
	if (otherlist > 0) {
		while(otherlist-- > 0) {
			wikiprint("</" other ">")
		}
	}

	# if we are needing more tags we open new
	if (thislist < tabcount) {
		while(thislist++ < tabcount) {
			wikiprint( "<" this ">")
		}
	# if we are needing less tags we close some
	} else if (thislist > tabcount) {
		while(thislist-- != tabcount) {
			wikiprint( "</" this ">")
		}
	}

	# output HTML tag for list
	if (tabcount) {
		sub(/^[#*]/,"")
		$0 = "\t<li" add_id() ">" $0
		wikiprint($0)
	}
	
	list[other] = 0
	list[this] = tabcount
}
function wikiprint(s)
{
	# TO DEBUG:	
print s > "/dev/stderr"
	wikibody=(wikibody  s "\n")
}
