# Package to parse and expand CFEngine-style templates
# Copyright (c) 2019 Maksym Tiurin
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.

namespace eval ::cftemplate {
	variable version 1.0
	variable classes [dict create "any" 1]
	variable lists [dict create]
	namespace export edit_template define undefine addlist dellist
}

package provide cftemplate $::cftemplate::version

proc ::cftemplate::parse_classes {classes} {
	# temporary replace || -> ##
	set classes [string map {"||" "##"} $classes]
	# replace & -> &&, | -> ||
	set classes [string map {"&" "&&" "|" "||"} $classes ]
	# replace . -> &&, ## -> ||
	set classes [string map {"." "&&" "##" "||"} $classes]
	if ![regexp -expanded {^[\w\s\!|&\(\)]+$} $classes] {
		# invalid expression string
		return 0
	}
	foreach cl [regexp -inline -all {\w+} $classes] {
		if [dict exists $::cftemplate::classes $cl] {
			set "CL_[set cl]" 1
		} else {
			set "CL_[set cl]" 0
		}
		regsub -all "\\m[set cl]\\M" $classes "\[set CL_[set cl]\]" classes
	}
	return [expr $classes]
}

proc ::cftemplate::substitute {text} {
	proc varname {v} {
		set vn [string range $v 2 end-1]
		if [regexp -expanded {(\w+\.\w+\.?)+} $vn] {
			# convert it to tcl variable name with namespace
			set vn [string map {"." "::"} $vn]
			set vn "::[set vn]"
		}
		return $vn
	}
	set v [regexp -expanded -all -inline {\$((\{[\w.]+\})|(\([\w.]+\)))} $text]
	set l [llength v]
	set varlist [list]
	set idx 0
	# regexp returns 4 values for each match
	while {$idx < $l} {
		lappend varlist [lindex $v $idx]
		incr idx 4
	}
	set result $text
	foreach vs $varlist {
		set v [varname $vs]
		if [dict exists $::cftemplate::lists $v] {
			# it's a list - iterate it
			set l [dict get $::cftemplate::lists $v]
			set ll [llength $l]
			incr ll -1
			set i 0
			while {$i < $ll} {
				set map [list $vs [lindex $l $i]]
				set r $result
				set result [string map $map $result]
				append result "\n" $r
				incr i
			}
			# last value
			set map [list $vs [lindex $l $i]]
			set result [string map $map $result]
		} elseif [info exists $v] {
			# variable exists
			set map [list $vs [set $v]]
			set result [string map $map $result]
		}
	}
	return $result
}

proc ::cftemplate::define {class_name} {
	dict set ::cftemplate::classes $class_name 1
}
proc ::cftemplate::undefine {class_name} {
	dict unset ::cftemplate::classes $class_name
}
proc ::cftemplate::addlist {name value} {
	dict set ::cftemplate::lists $name $value
}
proc ::cftemplate::dellist {name} {
	dict unset ::cftemplate::lists $name
}

proc ::cftemplate::edit_template {data} {
	set block [list]
	set result {}
	set class_is_true 1
	set start_block 0
	foreach l [split $data "\n"] {
		# check classes first
		if [regexp -expanded {^\[%CFEngine\s+([\w\s\!.|&\(\)]+)::\s+%\]$} $l res cl] {
			# class condition
			set class_is_true [::cftemplate::parse_classes $cl]
		} elseif {$class_is_true} {
			# do not skip this line
			if [regexp -expanded {^\[%CFEngine\s+BEGIN\s+%\]$} $l] {
				set start_block 1
			} elseif [regexp -expanded {^\[%CFEngine\s+END\s+%\]$} $l] {
				set start_block 0
				append result [::cftemplate::substitute [join $block "\n"]] "\n"
				set block [list]
			} elseif {$start_block} {
				lappend block $l
			} else {
				append result [::cftemplate::substitute $l] "\n"
			}
		}
	}
	if [llength $block] {
		append result [::cftemplate::substitute [join $block "\n"]] "\n"
	}
	return $result
}
# Local Variables:
# mode: tcl
# coding: utf-8-unix
# comment-column: 0
# comment-start: "# "
# comment-end: ""
# End:

