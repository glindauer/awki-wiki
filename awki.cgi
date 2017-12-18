#!/usr/bin/awk -f
################################################################################
# awkiawki - wikiwiki clone written in (n|g|m)awk
# $Id: awki.cgi,v 1.45 2004/07/13 16:34:45 olt Exp $
################################################################################
# Copyright (c) 2002 Oliver Tonnhofer (olt@bogosoft.com)
# See the file `COPYING' for copyright notice.
################################################################################
# GPL Note 12/2/17
# Because Safari web browser will download awki.cgi if URL is
# http://localhost:8080/awki.cgi
# we have to use http://localhost:8080/cgi-bin/awki.cgi instead.
# However, this script is set up so the root is supposed to be the
#	cgi-bin directory-- so the web server must be started from
#	cgi-bin, meaning that http://localhost:8080/awki.cgi
#	should be used.
# The solution is to place a soft link in cgi-bin directory as
#	ln -s . cgi-bin
# so http://localhost:8080/cgi-bin/awki.cgi works AND our root
#	remains the cgi-bin directory. (Link MUST be called cgi-bin to work.)

BEGIN {
	#            --- default options ---
	#    --- use awki.conf to override default settings ---
	#
	#	img_tag: HTML img tag  for picture in page header.
	localconf["img_tag"] = "<img src=\"/awki.png\" width=\"48\" height=\"39\" align=\"left\">"
	#	datadir: Directory for raw pagedata (must be writeable for the script).
	localconf["datadir"] = "./data/"
	#	imagedir: Directory for images (unlike datadir, must be absolute
	localconf["imagedir"]= "/images/"
	#	parser: Parsing script.
	localconf["parser"] = "./parser.awk"
	#   special_parser: Parser for special_* functions.
	localconf["special_parser"] = "./special_parser.awk"
	#	default_page: Name of the default_page.
	localconf["default_page"] = "FrontPage"
	#	show_changes: Number of changes listed by RecentChanges
	localconf["show_changes"] = 10
	#	max_post: Bytes accept by POST requests (to avoid DOS).
	localconf["max_post"] = 100000
	#	write_protection: Regex for write protected files
	#   	e.g.: "*", "PageOne|PageTwo|^.*NonEditable"
	#		HINT: to edit these protected pages, upload a .htaccess
	#		      protected awki.cgi script with write_protection = ""
	localconf["write_protection"] = ""
	#   css: HTTP URL for external CSS file.
	localconf["css"] = ""
	#   always_convert_spaces: If true, convert runs of 8 spaces to tab automatical.
	localconf["always_convert_spaces"] = 0
	#	date_cmd: Command for current date.
	localconf["date_cmd"] = "date '+%e %b. %G %R:%S %Z'"
	#	rcs: If true, rcs is used for revisioning.
	localconf["rcs"] = 0
	#	path: add path to PATH environment
	localconf["path"] = ""
	#            --- default options ---

	scriptname = ENVIRON["SCRIPT_NAME"]

	if (localconf["path"])
		ENVIRON["PATH"] = localconf["path"] ":" ENVIRON["PATH"]

	#load external configfile
	load_config(scriptname)

	# PATH_INFO contains page name
	if (ENVIRON["PATH_INFO"]) {
		query["page"] = ENVIRON["PATH_INFO"]
	}

	if (ENVIRON["REQUEST_METHOD"] == "POST") {
		if (ENVIRON["CONTENT_TYPE"] == "application/x-www-form-urlencoded") {
			if (ENVIRON["CONTENT_LENGTH"] < localconf["max_post"])
				bytes = ENVIRON["CONTENT_LENGTH"]
			else
				bytes = localconf["max_post"]

			# this cmd string will 
			# 1. Create a tempfile and place the name
			#	of it in "F"
			# 2. Use dd to copy one binary byte at a time
			#	into file "F" 
			#	(Note original command included
			#	 status=-noxfer which suppresses
			#	 the final "copied x bytes" info--
			#	 a. This isn't supported in bsd dd command
			#	 b. This isn't needed because of redirect
			#		to /dev/null
			# 3. Use cat to then pipe the contents of "F"
			#	for the awk getline function
			# 4. remove file "F" after the pipe
			# 5. getline puts the obtained (from web client)
			#	post information to query_string
	 		cmd = "F=`mktemp`; " \
	 			"dd ibs=" bytes " count=1 of=$F" \
	 			">/dev/null 2>/dev/null && " \
	 			"cat $F && rm -f $F" 
	# 		cmd = "F=`mktemp`; " \
	# 			"dd ibs=" bytes " status=noxfer count=1 of=$F" \
	# 			">/dev/null 2>/dev/null && " \
	# 			"cat $F && " \
	# 			"rm -f $F"
			cmd | getline query_str
			close (cmd)
		}
		if (ENVIRON["QUERY_STRING"]) {
			query_str = query_str "&" ENVIRON["QUERY_STRING"]
		}
	} else {
		if (ENVIRON["QUERY_STRING"])
			query_str = ENVIRON["QUERY_STRING"]
	}

	n = split(query_str, querys, "&")
	for (i=1; i<=n; i++) {
		split(querys[i], data, "=")
		query[data[1]] = data[2]
	}

	# (IMPORTANT for security!)
	query["page"] = clear_pagename(query["page"])
	query["revision"] = clear_revision(query["revision"])
	query["revision2"] = clear_revision(query["revision2"])
	query["string"] = clear_str(decode(query["string"]))

	if (!localconf["rcs"])
		query["revision"] = 0

	if (query["page"] == "")
		query["page"] = localconf["default_page"]

	query["filename"] = localconf["datadir"] query["page"]

	#check if page is editable
	special_pages = "FullSearch|PageList|RecentChanges|ChangesRSS"

	if (query["page"] ~ "("special_pages")") {
		special_page = 1
	} else if (!localconf["write_protection"] || query["page"] !~ "("localconf["write_protection"]")") {
		page_editable = 1
	}
	if(query["page"] == "ChangesRSS")
	{
		rss_page()
	}
	else {
		html_page()
	}
}

function html_page() {

	#print  "*** query[page] is " query["page"] > "/dev/stderr"

	# send the header to the webclient for display
	header(query["page"])

	# process the request from the webclient
	if (query["edit"] && page_editable)
		edit(query["page"], query["filename"], query["revision"])
	else if (query["save"] && query["text"] && page_editable)
		save(query["page"], query["text"], query["string"], query["filename"])
	else if (query["page"] ~ "PageList")
		special_index(localconf["datadir"])
	else if (query["page"] ~ "RecentChanges")
		special_changes(localconf["datadir"])
	else if (query["page"] ~ "FullSearch")
		special_search(query["string"],localconf["datadir"])
	else if (query["page"] && query["history"])
		special_history(query["page"], query["filename"])
	else if (query["page"] && query["diff"] && query["revision"])
		special_diff(query["page"], query["filename"], query["revision"], query["revision2"])
	else
	{
		parse(query["page"], query["filename"], query["revision"])
}

	footer(query["page"])
	 print "*************************************************************************\n*** Here's the page: ***\n*************************" > "/dev/stderr"
	 print wikipage > "/dev/stderr"
	print wikipage
}

function rss_page(   i,fn,date,link,host,proto,base_url) {
	host = ENVIRON["HTTP_HOST"]
	if("HTTPS" in ENVIRON)
		proto = "https"
	else
		proto = "http"

	base_url = proto "://" host scriptname

	wikiprint( "Content-Type: application/rss+xml; charset=utf-8\n")
	wikiprint( "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
	wikiprint( "<rss version=\"2.0\"><channel>")
	wikiprint( "<title>AwkiAwki at " base_url "</title>")
	wikiprint( "<link>" base_url "</link>")
	wikiprint( "<description>Recent Changes RSS feed for wiki</description>")

	i = 0
	while(i < 10 && ("ls -tlL "localconf["datadir"] | getline) > 0) {
		if($9 ~ /^[A-Z][a-z]+[A-Z][A-Za-z]*$/) {
			i++

			fn = $9
			date = $6 " " $7 " " $8 # ls -l's timstamp format can die in a fire.
			link = base_url "/" fn

			wikiprint(( "<item><title>" fn "</title>"))
			# FIXME: Getting ls to *portably* spit out an RFC-822 date isn't
			# possible.  feedvalidator.org doesn't seem to mind, so we'll ignore
			# the pubDate tag.
			#wikiprint( "<pubDate>" date "</pubDate>")
			wikiprint(( "<author>awki@"host" (AwkiAwki users)</author>"))
			wikiprint(( "<description>"fn" update at "date"</description>"))
			gsub(/[^0-9a-zA-Z]/, "_", date)
			wikiprint(( "<link>"link"</link><guid>"link"?"date"</guid>"))
			wikiprint(( "</item>"))
		}
	}

	wikiprint( "</channel></rss>\n")
}

# print header
function header(page) {
	wikiprint( "Content-type: text/html; charset=utf-8\n")
	wikiprint( "<html>\n<head>\n<title>" page "</title>")
	wikiprint( "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"Wiki Changes RSS\" href=\""scriptname"/ChangesRSS\"></link>")

	if (localconf["css"])
		wikiprint( "<link rel=\"stylesheet\" href=\"" localconf["css"] "\">")
	if (query["save"])
		wikiprint( "<meta http-equiv=\"refresh\" content=\"2,URL="scriptname"/"page"\">")
	wikiprint( "</head>\n<body>")
	wikiprint( "<h1>"localconf["img_tag"])
	wikiprint( "<a href=\""scriptname"/FullSearch?string="page"\">"page"</a></h1><hr>")
}

# print footer
function footer(page) {
	wikiprint( "<hr>")
	if (page_editable)
		wikiprint( "<a href=\""scriptname"?edit=true&amp;page="page"\">Edit "page"</a>")
	wikiprint( "<a href=\""scriptname"/"localconf["default_page"]"\">Top ("localconf["default_page"]")</a>")
	wikiprint( "<a href=\""scriptname"/PageList\">PageList</a>")
	#wikiprint( "<a href=\""scriptname"/RecentChanges\">RecentChanges</a>")
	#wikiprint( "<a href=\""scriptname"/ChangesRSS\">ChangesRSS</a>")
	#if (localconf["rcs"] && !special_page)
#		wikiprint( "<a href=\""scriptname"/"page"?history=true\">PageHistory</a>")
	wikiprint( "<form action=\""scriptname"/FullSearch\" method=\"GET\" align=\"right\">")
	wikiprint( "<input type=\"text\" name=\"string\">")
	wikiprint( "<input type=\"submit\" value=\"search\">")
	wikiprint( "</form>\n</body>\n</html>")
}

# send page to parser script
function parse(name, filename, revision) {

	# see if filename already exists
	if (system("test -f "filename) == 0 ) {
		#filename exists.
		if (revision) {
			wikiprint( "<em>Displaying old version ("revision") of <a href=\""scriptname"/" name "\">"name"</a>.</em>")

			cmd="co -q -p'"revision"' " filename " | "localconf["parser"] " -v datadir='"localconf["datadir"] "'"
			while (( cmd | getline sParsed) > 0)
				wikipage=(wikipage sParsed)	
			close(cmd)
		} else
		{
			# system(localconf["parser"] " -v datadir='"localconf["datadir"] "' " filename)

			# localconf["parser"] is name of .awk file that parses our wiki markup and generates HTML tags
			cmd=(localconf["parser"] " -v datadir='"localconf["datadir"] "' -v imagedir='"localconf["imagedir"] "' " filename)
			while (( cmd | getline sParsed) > 0)
				wikipage=(wikipage sParsed "\n" )	
			close(cmd)
		}
		#end of processing if filename exists
	}
}

function special_diff(page, filename, revision, revision2,   revisions) {
	if (system("[ -f "filename" ]") == 0) {

		wikiprint( "<em>Displaying diff between "revision)
		if (revision2)
			wikiprint( " and "revision2)
		else
			wikiprint( " and current version")
		wikiprint( " of <a href=\""scriptname"/"page "\">"page"</a>.</em>")
		if (revision2)
			revisions = "-r" revision " -r" revision2
		else
			revisions = "-r" revision
		system("rcsdiff "revisions" -u "filename" | " localconf["special_parser"] " -v special_diff='"page"'")
	}
}

# print edit form
function edit(page, filename, revision,   cmd) {
	if (revision)
		wikiprint( "<p><small><em>If you save previous versions, you'll overwrite the current page.</em></small>")
	wikiprint( "<form action=\""scriptname"?save=true&amp;page="page"\" method=\"POST\">")
	wikiprint( "<textarea name=\"text\" rows=25 cols=80>")
	# insert current page into textarea
	if (revision) {
		cmd = "co -q -p'"revision"' " filename
		while ((cmd | getline) >0)
			wikiprint()
		close(cmd)
	} else {
		while ((getline sLine < filename) >0)
			wikiprint(sLine) 
		close(filename)
	}
	wikiprint( "</textarea><br />")
	wikiprint( "<input type=\"submit\" value=\"save\">")
	if (localconf["rcs"])
		wikiprint( "Comment: <input type=\"text\" name=\"string\" maxlength=80 size=50>")
	if (! localconf["always_convert_spaces"])
		wikiprint( "<br>Convert runs of 8 spaces to Tab <input type=\"checkbox\" name=\"convertspaces\" checked>")
	wikiprint( "</form>")
	wikiprint( "<div class=\"FormKey\">\n")
	wikiprint("<strong>WikiMarkup tags start with commas (,); use semicolon instead of comma to make link in contents.<br>")
	wikiprint("Fonts:</strong>,/<em>italic</em>,/  ,.<strong>bold</strong>,.  ,_<u>underline</u>,_<br>")
	wikiprint(" Start a line with a space to obtain preformatted lines. You can't use certain other tags (such as lists) in preformatted lines.<br>");
	wikiprint("<strong>Format:</strong>,#= to indent; # is optional amount to indent.<br")
	wikiprint(",- inserts a horizontal rule. A blank line starts a new paragraph.<br>")
	wikiprint("<strong>Heading:</strong> ,#&lt;space&gt; where # is header level from 1 to 6<br>")
	wikiprint("<strong>Lists:</strong> ,* for bulleted list, ,# for numbered list (this time use literal hash sign)<br>")
	wikiprint(" Nesting of one list inside another is accomplished by prefixing additional commas<br>");
	wikiprint(" or semicolons in front of the * or #.</br>")
	wikiprint("<strong>Links:</strong> JoinCapitalizedWords; url (http, https, ftp, gopher, mailto, news)")
}

# save page
function save(page, text, comment, filename,   dtext, date) {
	dtext = decode(text);
	if ( localconf["always_convert_spaces"] || query["convertspaces"] == "on")
		gsub(/        /, "\t", dtext);
	# UNCOMMENT BELOW TO DEBUG
	# print "Executing print dtext > filename" > "/dev/stderr"
	# print "filename is " filename " and " >"/dev/stderr"
	# print "dtext is" > "/dev/stderr"
	# print dtext >"/dev/stderr"

	# this is what actually saves the page
	print dtext > filename

	if (localconf["rcs"]) {
		localconf["date_cmd"] | getline date
		system("ci -q -t-"page" -l -m'"ENVIRON["REMOTE_ADDR"] ";;" date ";;"comment"' " filename)
	}
	wikiprint( "Saved <a href=\""scriptname"/"page"\">"page"</a>")
}

# PageList link was clicked: list all pages using special_parser.awk
function special_index(datadir) {
	lc=localconf["special_parser"]
 	cmd="ls -1 " datadir " | " localconf["special_parser"] " -v special_index=yes"
	while (( cmd | getline sParsed) > 0)
		wikipage=(wikipage sParsed)	
	close(cmd)

}

# list pages with last modified time (sorted by date)
function special_changes(datadir,   date) {
	localconf["date_cmd"] | getline date
	wikiprint( "<p>current date:", date "<p>")
	system("ls -tlL "datadir" | " localconf["special_parser"] " -v special_changes=" localconf["show_changes"])
}

function special_search(name,datadir) {
	cmd="grep -il '"name"' "datadir"* | " localconf["special_parser"] " -v special_search=yes"
	while (( cmd | getline sParsed) > 0)
		wikipage=(wikipage sParsed)	
	close(cmd)
}

function special_history(name, filename) {
	wikiprint( "<p>last changes on <a href=\""scriptname"/" name "\">"name"</a><p>")
	system("rlog " filename " | " localconf["special_parser"] " -v special_history="name)

	wikiprint( "<p>Show diff between:")
	wikiprint( "<form action=\""scriptname"/\" method=\"GET\">")
	wikiprint( "<input type=\"hidden\" name=\"page\" value=\""name"\">")
	wikiprint( "<input type=\"hidden\" name=\"diff\" value=\"true\">")
	wikiprint( "<input type=\"text\" name=\"revision\" size=5>")
	wikiprint( "<input type=\"text\" name=\"revision2\" size=5>")
	wikiprint( "<input type=\"submit\" value=\"diff\">")
	wikiprint( "</form></p>")
}

# remove '"` characters from string
# *** !Important for Security! ***
function clear_str(str) {
	gsub(/['`"]/, "", str)
	if (length(str) > 80)
		return substr(str, 1, 80)
	else
		return str
}

# retrun the pagename
# *** !Important for Security! ***
function clear_pagename(str) {
	if (match(str, /[A-Z][a-z]+[A-Z][A-Za-z]*/))
		return substr(str, RSTART, RLENGTH)
	else
		return ""
}

# return revision numbers
# *** !Important for Security! ***
function clear_revision(str) {
	if (match(str, /[1-9]\.[0-9]+/))
		return substr(str, RSTART, RLENGTH)
	else
		return ""
}

# decode urlencoded string
function decode(text,   hex, i, hextab, decoded, len, c, c1, c2, code) {

	split("0 1 2 3 4 5 6 7 8 9 a b c d e f", hex, " ")
	for (i=0; i<16; i++) hextab[hex[i+1]] = i

	# urldecode function from Heiner Steven
	# http://www.shelldorado.com/scripts/cmds/urldecode

	# decode %xx to ASCII char
	decoded = ""
	i = 1
	len = length(text)

	while ( i <= len ) {
	    c = substr (text, i, 1)
		if ( c == "%" ) {
			if ( i+2 <= len ) {
				c1 = tolower(substr(text, i+1, 1))
				c2 = tolower(substr(text, i+2, 1))
				if ( hextab [c1] != "" || hextab [c2] != "" ) {
					if ( (c1 >= 2 && c1 != 7) || (c1 == 7 && c2 != "f") || (c1 == 0 && c2 ~ "[9acd]") ){
						code = 0 + hextab [c1] * 16 + hextab [c2] + 0
						c = sprintf ("%c", code)
					} else {
						c = " "
					}
					i = i + 2
			   }
			}
	    } else if ( c == "+" ) {	# special handling: "+" means " "
	    	c = " "
	    }
	    decoded = decoded c
	    ++i
	}

	# change linebreaks to \n
	gsub(/\r\n/, "\n", decoded)

	# remove last linebreak
	sub(/[\n\r]*$/,"",decoded)

	return decoded
}

#load configfile
function load_config(script,   configfile,key,value) {
	configfile = script
	#remove trailing / ('/awki/awki.cgi/' -> '/awki/awki.cgi')
	sub(/\/$/, "", configfile)
	#remove path ('/awki/awki.cgi' -> 'awki.cgi')
	sub(/^.*\//, "", configfile)
	#remove suffix ('awki.cgi' -> 'awki')
	sub(/\.[^.]*$/,"", configfile)
	# append .conf suffix
	configfile = configfile ".conf"

	#read configfile
	while((getline < configfile) >0) {
		if ($0 ~ /^#/) continue #ignore comments

		if (match($0,/[ \t]*=[ \t]*/)) {
			key = substr($0, 1, RSTART-1)
			sub(/^[ \t]*/, "", key)
			value = substr($0, RSTART+RLENGTH)
			sub(/[ \t]*$/, "", value)
			if (sub(/^"/, "", value))
				sub(/"$/, "", value)
			#set localconf variables
			localconf[key] = value

		}
	}
}
function wikiprint(s)
{
	# DEBUG	print s > "/dev/stderr"
	wikipage=(wikipage s "\n")
}

