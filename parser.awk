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

# HTML entities for <, > and &
/[&<>]/ { gsub(/&/, "\\&amp;");	gsub(/</, "\\&lt;"); gsub(/>/, "\\&gt;"); wikiprint(); }

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


# remove six single quotes (Wiki''''''Links)
{ gsub(/''''''/,""); }

# emphasize text in single-quotes 
/'''/ { gsub(/'''('?'?[^'])*'''/, "<b>&</b>"); gsub(/'''/,""); wikiprint(); }
/''/  { gsub(/''('?[^'])*''/, "<i>&</i>"); gsub(/''/,""); wikiprint(); }

#lists
/^~+[*]/ { close_tags("list"); parse_list("ul", "ol"); wikiprint(); next;}
/^~+[#1]/ { close_tags("list"); parse_list("ol", "ul"); wikiprint(); next;}
/^\t+[*]/ { close_tags("list"); parse_list("ul", "ol"); wikiprint(); next;}
/^\t+[#1]/ { close_tags("list"); parse_list("ol", "ul"); wikiprint(); next;}

#headings
/^-[1-6]/ { headerLevel=substr($0,2,1); $0 = "<h" headerLevel ">" substr($0, 3) "</h" headerLevel ">"; close_tags(); wikiprint($0); next; }

# horizontal line
/^----/ { sub(/^----+/, "<hr>"); blankline = 1; close_tags(); wikiprint($0); next; }

/^ / { 
	close_tags("pre");
	if (pre != 1) {
		wikiprint( "<pre>\n" $0); pre = 1
		blankline = 0
	} else { 
		if (blankline==1) {
			wikiprint(); blankline = 0
		}
		wikiprint($0);
	}
	next;
}

NR == 1 { wikiprint( "<p>"); }
{
	close_tags();
	
	# print paragraph when blankline registered
	if (blankline==1) {
		wikiprint("<p>");
		blankline=0;
	}

	#print line
	wikiprint($0);
}

END {
	$0 = ""
	close_tags();
	wikiprint();
}

function close_tags(not) {

	# if list is parsed this line print it
	if (not !~ "list") {
		if (list["ol"] > 0) {
			parse_list("ol", "ul")
		} else if (list["ul"] > 0) {
			parse_list("ul", "ol")
		} 
	}
	# close monospace
	if (not !~ "pre") {
		if (pre == 1) {
			wikiprint("</pre>")
			pre = 0
		}
	}
}
function parse_list(this, other) {
	#    The wikimarkup for a list is
	# ~* First bullet item
        # ~* Next bullet item
   	#    OR, for a numbered list,
	# ~1 first numbered item
        # ~2 second numbered item
        #    and so on.
        # tabs can be used instead of tildas.
        # Lists can be nested in lists by prefixing more tabs or tildas. 
	# list[] variable tells level of the nest we are in.
        # this and other correspond to HTML tag: 
	#    ("ul" for unordered list, "ol" for ordered list)
	thislist = list[this]
	otherlist = list[other]
	tabcount = 0

	# while a tab prefixes our list marker, remove the tab and add to count 
	while(/^\t+[#1*]/) {
		sub(/^\t/,"")
		tabcount++
	}
	# If a tilda (abbreviation for tab) prefixes, remove ~ and add to count
	while(/^~+[#1*]/) {
		sub(/~/,"")
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
		sub(/^[#1*]/,"")
		$0 = "\t<li>" $0
		wikiprint($0)
	}
	
	list[other] = 0
	list[this] = tabcount
}
function wikiprint(s)
{
	print s > "/dev/stderr"
	print s;
#	wikibody=(wikibody s "\n")
}
