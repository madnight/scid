###
### analysis.tcl: part of Scid.
### Copyright (C) 1999-2003  Shane Hudson.
### Copyright (C) 2007  Pascal Georges

######################################################################
### Analysis window: uses a chess engine to analyze the board.

# analysis(logMax):
#   The maximum number of log message lines to be saved in a log file.
set analysis(logMax) 500

# analysis(log_stdout):
#   Set this to 1 if you want Scid-Engine communication log messages
#   to be echoed to stdout.
#
set analysis(log_stdout) 0

set useAnalysisBook 1
set analysisBookSlot 1
set useAnalysisBookName ""
set wentOutOfBook 0

set isBatch 0
set batchEnd 1
set isBatchOpening 0
set isBatchOpeningMoves 12
set stack ""

################################################################################
# The different threshold values for !? ?? += etc
array set informant {}
set informant("!?") 0.5
set informant("?") 1.5
set informant("??") 3.0
set informant("?!") 0.5
set informant("+=") 0.5
set informant("+/-") 1.5
set informant("+-") 3.0
set informant("++-") 5.5

################################################################################
#
################################################################################
# resetEngine:
#   Resets all engine-specific data.
#
proc resetEngine {n} {
  global analysis
  set analysis(pipe$n) ""             ;# Communication pipe file channel
  set analysis(seen$n) 0              ;# Seen any output from engine yet?
  set analysis(seenEval$n) 0          ;# Seen evaluation line yet?
  set analysis(score$n) 0             ;# Current score in centipawns
  set analysis(prevscore$n) 0         ;# Immediately previous score in centipawns
  set analysis(prevmoves$n) ""        ;# Immediately previous best line out from engine
  set analysis(nodes$n) 0             ;# Number of (kilo)nodes searched
  set analysis(depth$n) 0             ;# Depth in ply
  set analysis(prev_depth$n) 0        ;# Previous depth
  set analysis(time$n) 0              ;# Time in centisec (or sec; see below)
  set analysis(moves$n) ""            ;# PV (best line) output from engine
  set analysis(movelist$n) {}         ;# Moves to reach current position
  set analysis(nonStdStart$n) 0       ;# Game has non-standard start
  set analysis(has_analyze$n) 0       ;# Engine has analyze command
  set analysis(has_setboard$n) 0      ;# Engine has setboard command
  set analysis(send_sigint$n) 0       ;# Engine wants INT signal
  set analysis(wants_usermove$n) 0    ;# Engine wants "usermove" before moves
  set analysis(isCrafty$n) 0          ;# Engine appears to be Crafty
  set analysis(wholeSeconds$n) 0      ;# Engine times in seconds not centisec
  set analysis(analyzeMode$n) 0       ;# Scid has started analyze mode
  set analysis(invertScore$n) 1       ;# Score is for side to move, not white
  set analysis(automove$n) 0
  set analysis(automoveThinking$n) 0
  set analysis(automoveTime$n) 4000
  set analysis(lastClicks$n) 0
  set analysis(after$n) ""
  set analysis(log$n) ""              ;# Log file channel
  set analysis(logCount$n) 0          ;# Number of lines sent to log file
  set analysis(wbEngineDetected$n) 0  ;# Is this a special Winboard engine?
  # set analysis(priority$n) normal     ;# CPU priority: idle/normal
  set analysis(multiPV$n) {}  ;# multiPV list sorted : depth score moves
  set ::uci::uciInfo(pvlist$n) {} ;# same thing but with raw UCI moves
  set analysis(uci$n) 0 ;# UCI engine
  # UCI engine options in format ( name min max ). This is not engine config but its capabilities
  set analysis(uciOptions$n) {}
  # the number of lines in multiPV. If =1 then act the traditional way
  set analysis(multiPVCount$n) 4 ;# number of N-best lines
  set analysis(index$n) 0 ; # the index of engine in engine list
  set analysis(uciok$n) 0 ; # uciok sent by engine in response to uci command
  set analysis(name$n) "" ; # engine name
  set analysis(processInput$n) 0 ; # the time of the last processed event
  set analysis(waitForBestMove$n) 0
  set analysis(waitForReadyOk$n) 0
  set analysis(waitForUciOk$n) 0
  set analysis(movesDisplay$n) 1 ;# if false, hide engine lines, only display scores
}

resetEngine 1
resetEngine 2
set analysis(priority1) normal     ;# CPU priority: idle/normal
set analysis(priority2) normal     ;# CPU priority: idle/normal

set annotateMode 0
set annotateModeButtonValue 0 ; # feedback of annotate mode

set annotateMoves all
set annotateBlunders blundersonly

################################################################################
# calculateNodes:
#   Divides string-represented node count by 1000
################################################################################
proc calculateNodes {{n}} {
  set len [string length $n]
  if { $len < 4 } {
    return 0
  } else {
    set shortn [string range $n 0 [expr {$len - 4}]]
    scan $shortn "%d" nd
    return $nd
  }
}


# resetAnalysis:
#   Resets the analysis statistics: score, depth, etc.
#
proc resetAnalysis {{n 1}} {
  global analysis
  set analysis(score$n) 0
  set analysis(scoremate$n) 0
  set analysis(nodes$n) 0
  set analysis(prev_depth$n) 0
  set analysis(depth$n) 0
  set analysis(time$n) 0
  set analysis(moves$n) ""
  set analysis(multiPV$n) {}
}

namespace eval enginelist {}

set engines(list) {}

# engine:
#   Adds an engine to the engine list.
#   Calls to this function will be found in the user engines.lis
#   file, which is sourced below.
#
proc engine {arglist} {
  global engines
  array set newEngine {}
  foreach {attr value} $arglist {
    set newEngine($attr) $value
  }
  # Check that required attributes exist:
  if {! [info exists newEngine(Name)]} { return  0 }
  if {! [info exists newEngine(Cmd)]} { return  0 }
  if {! [info exists newEngine(Dir)]} { return  0 }
  # Fill in optional attributes:
  if {! [info exists newEngine(Args)]} { set newEngine(Args) "" }
  if {! [info exists newEngine(Elo)]} { set newEngine(Elo) 0 }
  if {! [info exists newEngine(Time)]} { set newEngine(Time) 0 }
  if {! [info exists newEngine(URL)]} { set newEngine(URL) "" }
  # puts this option here for compatibility with previous file format (?!)
  if {! [info exists newEngine(UCI)]} { set newEngine(UCI) 0 }
  if {! [info exists newEngine(UCIoptions)]} { set newEngine(UCIoptions) "" }
  
  lappend engines(list) [list $newEngine(Name) $newEngine(Cmd) \
      $newEngine(Args) $newEngine(Dir) \
      $newEngine(Elo) $newEngine(Time) \
      $newEngine(URL) $newEngine(UCI) $newEngine(UCIoptions)]
  return 1
}

# ::enginelist::read
#   Reads the user Engine list file.
#
proc ::enginelist::read {} {
  catch {source [scidConfigFile engines]}
}

# ::enginelist::write:
#   Writes the user Engine list file.
#
proc ::enginelist::write {} {
  global engines ::uci::newOptions
  
  set enginesFile [scidConfigFile engines]
  set enginesBackupFile [scidConfigFile engines.bak]
  # Try to rename old file to backup file and open new file:
  catch {file rename -force $enginesFile $enginesBackupFile}
  if {[catch {open $enginesFile w} f]} {
    catch {file rename $enginesBackupFile $enginesFile}
    return 0
  }
  
  puts $f "\# Analysis engines list file for Scid [sc_info version] with UCI support"
  puts $f ""
  foreach e $engines(list) {
    set name [lindex $e 0]
    set cmd [lindex $e 1]
    set args [lindex $e 2]
    set dir [lindex $e 3]
    set elo [lindex $e 4]
    set time [lindex $e 5]
    set url [lindex $e 6]
    set uci [lindex $e 7]
    set opt [lindex $e 8]
    puts $f "engine {"
      puts $f "  Name [list $name]"
      puts $f "  Cmd  [list $cmd]"
      puts $f "  Args [list $args]"
      puts $f "  Dir  [list $dir]"
      puts $f "  Elo  [list $elo]"
      puts $f "  Time [list $time]"
      puts $f "  URL  [list $url]"
      puts $f "  UCI [list $uci]"
      puts $f "  UCIoptions [list $opt]"
      puts $f "}"
    puts $f ""
  }
  close $f
  return 1
}

# Read the user Engine List file now:
#
catch { ::enginelist::read }
if {[llength $engines(list)] == 0} {
  # No engines, so set up a default engine list with Scidlet and Crafty:
  set cmd scidlet
  if {$::windowsOS} {
    set cmd [file join $::scidExeDir scidlet.exe]
  }
  engine [list \
      Name Scidlet \
      Cmd  $cmd \
      Dir  . \
      ]
  set cmd crafty
  if {$::windowsOS} { set cmd wcrafty.exe }
  engine [list \
      Name Crafty \
      Cmd  $cmd \
      Dir  . \
      URL  ftp://ftp.cis.uab.edu/pub/hyatt/ \
      ]
}

# ::enginelist::date
#   Given a time in seconds since 1970, returns a
#   formatted date string.
proc ::enginelist::date {time} {
  return [clock format $time -format "%a %b %d %Y %H:%M"]
}

# ::enginelist::sort
#   Sort the engine list.
#   If the engine-open dialog is open, its list is updated.
#   The type defaults to the current engines(sort) value.
#
proc ::enginelist::sort {{type ""}} {
  global engines
  
  if {$type == ""} {
    set type $engines(sort)
  } else {
    set engines(sort) $type
  }
  switch $type {
    Name {
      set engines(list) [lsort -dictionary -index 0 $engines(list)]
    }
    Elo {
      set engines(list) [lsort -integer -decreasing -index 4 $engines(list)]
    }
    Time {
      set engines(list) [lsort -integer -decreasing -index 5 $engines(list)]
    }
  }
  
  # If the Engine-open dialog is open, update it:
  #
  set w .enginelist
  if {! [winfo exists $w]} { return }
  set f $w.list.list
  $f delete 0 end
  set count 0
  foreach engine $engines(list) {
    incr count
    set name [lindex $engine 0]
    set elo [lindex $engine 4]
    set time [lindex $engine 5]
    set uci [lindex $engine 7]
    set date [::enginelist::date $time]
    set text [format "%2u. %-21s " $count $name]
    set eloText "    "
    if {$elo > 0} { set eloText [format "%4u" $elo] }
    append text $eloText
    set timeText "  "
    if {$time > 0} { set timeText "   $date" }
    append text $timeText
    $f insert end $text
  }
  $f selection set 0
  
  # Show the sorted column heading in red text:
  $w.title configure -state normal
  foreach i {Name Elo Time} {
    $w.title tag configure $i -foreground {}
  }
  $w.title tag configure $engines(sort) -foreground red
  $w.title configure -state disabled
}

# ::enginelist::choose
#   Select an engine from the Engine List.
#   Returns an integer index into the engines(list) list variable.
#   If no engine is selected, returns the empty string.
#
proc ::enginelist::choose {} {
  global engines
  set w .enginelist
  toplevel $w
  wm title $w "Scid: [tr ToolsAnalysis]"
  label $w.flabel -text $::tr(EngineList:) -font font_Bold
  pack $w.flabel -side top
  
  pack [frame $w.buttons] -side bottom -pady 6 -fill x
  frame $w.rule -height 2 -borderwidth 2 -relief sunken -background white
  pack $w.rule -side bottom -fill x -pady 5
  
  # Set up title frame for sorting the list:
  text $w.title -width 55 -height 1 -font font_Fixed -relief flat \
      -cursor top_left_arrow
  $w.title insert end "    "
  $w.title insert end $::tr(EngineName) Name
  for {set i [string length $::tr(EngineName)]} {$i < 21} { incr i } {
    $w.title insert end " "
  }
  $w.title insert end "  "
  $w.title insert end $::tr(EngineElo) Elo
  for {set i [string length $::tr(EngineElo)]} {$i < 4} { incr i } {
    $w.title insert end " "
  }
  $w.title insert end "  "
  $w.title insert end $::tr(EngineTime) Time
  foreach i {Name Elo Time} {
    $w.title tag bind $i <Any-Enter> \
        "$w.title tag configure $i -background yellow"
    $w.title tag bind $i <Any-Leave> \
        "$w.title tag configure $i -background {}"
    $w.title tag bind $i <1> [list ::enginelist::sort $i]
  }
  $w.title configure -state disabled
  pack $w.title -side top -fill x
  
  # The list of choices:
  set f $w.list
  pack [frame $f] -side top -expand yes -fill both
  listbox $f.list -height 10 -width 55  -selectmode browse \
      -background white -setgrid 1 \
      -yscrollcommand "$f.ybar set" -font font_Fixed -exportselection 0
  bind $f.list <Double-ButtonRelease-1> "$w.buttons.ok invoke; break"
  scrollbar $f.ybar -command "$f.list yview"
  pack $f.ybar -side right -fill y
  pack $f.list -side top -fill both -expand yes
  $f.list selection set 0
  
  set f $w.buttons
  dialogbutton $f.add -text $::tr(EngineNew...) -command {::enginelist::edit -1}
  dialogbutton $f.edit -text $::tr(EngineEdit...) -command {
    ::enginelist::edit [lindex [.enginelist.list.list curselection] 0]
  }
  dialogbutton $f.delete -text $::tr(Delete...) -command {
    ::enginelist::delete [lindex [.enginelist.list.list curselection] 0]
  }
  label $f.sep -text "   "
  dialogbutton $f.ok -text "OK" -command {
    set engines(selection) [lindex [.enginelist.list.list curselection] 0]
    destroy .enginelist
  }
  dialogbutton $f.cancel -text $::tr(Cancel) -command {
    set engines(selection) ""
    destroy .enginelist
  }
  packbuttons right $f.cancel $f.ok
  pack $f.add $f.edit $f.delete -side left -padx 1
  
  ::enginelist::sort
  ::utils::win::Centre $w
  focus $w.list.list
  wm protocol $w WM_DELETE_WINDOW "destroy $w"
  bind $w <F1> { helpWindow Analysis List }
  bind $w <Escape> "destroy $w"
  bind $w.list.list <Return> "$w.buttons.ok invoke; break"
  set engines(selection) ""
  catch {grab $w}
  tkwait window $w
  return $engines(selection)
}

# ::enginelist::setTime
#   Sets the last-opened time of the engine specified by its
#   index in the engines(list) list variable.
#   The time should be in standard format (seconds since 1970)
#   and defaults to the current time.
#
proc ::enginelist::setTime {index {time -1}} {
  global engines
  set e [lindex $engines(list) $index]
  if {$time < 0} { set time [clock seconds] }
  set e [lreplace $e 5 5 $time]
  set engines(list) [lreplace $engines(list) $index $index $e]
}

trace variable engines(newElo) w [list ::utils::validate::Integer [sc_info limit elo] 0]

# ::enginelist::delete
#   Removes an engine from the list.
#
proc ::enginelist::delete {index} {
  global engines
  if {$index == ""  ||  $index < 0} { return }
  set e [lindex $engines(list) $index]
  set msg "Name: [lindex $e 0]\n"
  append msg "Command: [lindex $e 1]\n\n"
  append msg "Do you really want to remove this engine from the list?"
  set answer [tk_messageBox -title Scid -icon question -type yesno \
      -message $msg]
  if {$answer == "yes"} {
    set engines(list) [lreplace $engines(list) $index $index]
    ::enginelist::sort
    ::enginelist::write
  }
}

# ::enginelist::edit
#   Opens a dialog for editing an existing engine list entry (if
#   index >= 0), or adding a new entry (if index is -1).
#
proc ::enginelist::edit {index} {
  global engines
  if {$index == ""} { return }
  
  if {$index >= 0  ||  $index >= [llength $engines(list)]} {
    set e [lindex $engines(list) $index]
  } else {
    set e [list "" "" "" . 0 0 "" 0]
  }
  
  set engines(newIndex) $index
  set engines(newName) [lindex $e 0]
  set engines(newCmd) [lindex $e 1]
  set engines(newArgs) [lindex $e 2]
  set engines(newDir) [lindex $e 3]
  set engines(newElo) [lindex $e 4]
  set engines(newTime) [lindex $e 5]
  set engines(newURL) [lindex $e 6]
  set engines(newUCI) [lindex $e 7]
  set engines(newUCIoptions) [lindex $e 8]
  
  set engines(newDate) $::tr(None)
  if {$engines(newTime) > 0 } {
    set engines(newDate) [::enginelist::date $engines(newTime)]
  }
  
  set w .engineEdit
  toplevel $w
  wm title $w Scid
  
  set f [frame $w.f]
  pack $f -side top -fill x -expand yes
  set row 0
  foreach i {Name Cmd Args Dir URL} {
    label $f.l$i -text $i
    if {[info exists ::tr(Engine$i)]} {
      $f.l$i configure -text $::tr(Engine$i)
    }
    entry $f.e$i -textvariable engines(new$i) -width 40
    bindFocusColors $f.e$i
    grid $f.l$i -row $row -column 0 -sticky w
    grid $f.e$i -row $row -column 1 -sticky we
    
    # Browse button for choosing an executable file:
    if {$i == "Cmd"} {
      button $f.b$i -text "..." -command {
        if {$::windowsOS} {
          set scid_temp(filetype) {
            {"Applications" {".bat" ".exe"} }
            {"All files" {"*"} }
          }
        } else {
          set scid_temp(filetype) {
            {"All files" {"*"} }
          }
        }
        set scid_temp(cmd) [tk_getOpenFile -initialdir $engines(newDir) \
            -title "Scid: [tr ToolsAnalysis]" -filetypes $scid_temp(filetype)]
        if {$scid_temp(cmd) != ""} {
          set engines(newCmd) $scid_temp(cmd)
          # if {[string first " " $scid_temp(cmd)] >= 0} {
          # The command contains spaces, so put it in quotes:
          # set engines(newCmd) "\"$scid_temp(cmd)\""
          # }
          # Set the directory from the executable path if possible:
          set engines(newDir) [file dirname $scid_temp(cmd)]
          if {$engines(newDir) == ""} [ set engines(newDir) .]
        }
      }
      grid $f.b$i -row $row -column 2 -sticky we
    }
    
    if {$i == "Dir"} {
      button $f.current -text " . " -command {
        set engines(newDir) .
      }
      button $f.user -text "~/.scid" -command {
        set engines(newDir) $scidUserDir
      }
      if {$::windowsOS} {
        $f.user configure -text "scid.exe dir"
      }
      grid $f.current -row $row -column 2 -sticky we
      grid $f.user -row $row -column 3 -sticky we
    }
    
    if {$i == "URL"} {
      button $f.bURL -text [tr FileOpen] -command {
        if {$engines(newURL) != ""} { openURL $engines(newURL) }
      }
      grid $f.bURL -row $row -column 2 -sticky we
    }
    
    incr row
  }
  
  grid columnconfigure $f 1 -weight 1
  
  checkbutton $f.cbUci -text UCI -variable engines(newUCI)
  button $f.bConfigUCI -text $::tr(ConfigureUCIengine) -command {
    ::uci::uciConfig 2 [ toAbsPath $engines(newCmd) ] $engines(newArgs) \
        [ toAbsPath $engines(newDir) ] $engines(newUCIoptions)
  }
  # Mark required fields:
  $f.lName configure -font font_Bold
  $f.lCmd configure -font font_Bold
  $f.lDir configure -font font_Bold
  $f.cbUci configure -font font_Bold
  
  label $f.lElo -text $::tr(EngineElo)
  entry $f.eElo -textvariable engines(newElo) -justify right -width 5
  bindFocusColors $f.eElo
  grid $f.lElo -row $row -column 0 -sticky w
  grid $f.eElo -row $row -column 1 -sticky w
  incr row
  grid $f.cbUci -row $row -column 0 -sticky w
  grid $f.bConfigUCI -row $row -column 1 -sticky w
  incr row
  
  label $f.lTime -text $::tr(EngineTime)
  label $f.eTime -textvariable engines(newDate) -anchor w -width 1
  grid $f.lTime -row $row -column 0 -sticky w
  grid $f.eTime -row $row -column 1 -sticky we
  button $f.clearTime -text $::tr(Clear) -command {
    set engines(newTime) 0
    set engines(newDate) $::tr(None)
  }
  button $f.nowTime -text $::tr(Update) -command {
    set engines(newTime) [clock seconds]
    set engines(newDate) [::enginelist::date $engines(newTime)]
  }
  grid $f.clearTime -row $row -column 2 -sticky we
  grid $f.nowTime -row $row -column 3 -sticky we
  
  addHorizontalRule $w
  set f [frame $w.buttons]
  button $f.ok -text OK -command {
    if {[string trim $engines(newName)] == ""  ||
      [string trim $engines(newCmd)] == ""  ||
      [string trim $engines(newDir)] == ""} {
      tk_messageBox -title Scid -icon info \
          -message "The Name, Command and Directory fields must not be empty."
    } else {
      set newEntry [list $engines(newName) $engines(newCmd) \
          $engines(newArgs) $engines(newDir) \
          $engines(newElo) $engines(newTime) \
          $engines(newURL) $engines(newUCI) $::uci::newOptions ]
      if {$engines(newIndex) < 0} {
        lappend engines(list) $newEntry
      } else {
        set engines(list) [lreplace $engines(list) \
            $engines(newIndex) $engines(newIndex) $newEntry]
      }
      destroy .engineEdit
      ::enginelist::sort
      ::enginelist::write
    }
  }
  button $f.cancel -text $::tr(Cancel) -command "destroy $w"
  pack $f -side bottom -fill x
  pack $f.cancel $f.ok -side right -padx 2 -pady 2
  label $f.required -font font_Small -text $::tr(EngineRequired)
  pack $f.required -side left
  
  bind $w <Return> "$f.ok invoke"
  bind $w <Escape> "destroy $w"
  bind $w <F1> { helpWindow Analysis List }
  focus $w.f.eName
  wm resizable $w 1 0
  catch {grab $w}
}
# ################################################################################
#
################################################################################
proc configAnnotation {} {
  global autoplayDelay tempdelay blunderThreshold annotateModeButtonValue
  
  set w .configAnnotation
  if { [winfo exists $w] } { focus $w ; return }
  if { ! $annotateModeButtonValue } { ; # end annotation
    toggleAutoplay
    return
  }
  
  trace variable blunderThreshold w {::utils::validate::Regexp {^[0-9]*\.?[0-9]*$}}
  
  set tempdelay [expr {$autoplayDelay / 1000.0}]
  toplevel $w
  wm title $w "Scid"
  wm resizable $w 0 0
  label $w.label -text $::tr(AnnotateTime:)
  pack $w.label -side top -pady 5 -padx 5
  spinbox $w.spDelay -background white -width 4 -textvariable tempdelay -from 1 -to 300 -increment 1
  pack $w.spDelay -side top -pady 5
  bind $w <Escape> { .configAnnotation.buttons.cancel invoke }
  bind $w <Return> { .configAnnotation.buttons.ok invoke }
  
  addHorizontalRule $w
  label $w.avlabel -text $::tr(AnnotateWhich:)
  radiobutton $w.all -text $::tr(AnnotateAll) -variable annotateMoves -value all -anchor w
  radiobutton $w.white -text $::tr(AnnotateWhite) -variable annotateMoves -value white -anchor w
  radiobutton $w.black -text $::tr(AnnotateBlack) -variable annotateMoves -value black -anchor w
  radiobutton $w.allmoves -text $::tr(AnnotateAllMoves) -variable annotateBlunders -value allmoves -anchor w
  radiobutton $w.notbest -text $::tr(AnnotateNotBest) -variable annotateBlunders -value notbest -anchor w
  radiobutton $w.blundersonly -text $::tr(AnnotateBlundersOnly) \
      -variable annotateBlunders -value blundersonly -anchor w
  pack $w.avlabel -side top
  pack $w.all $w.white $w.black $w.allmoves $w.notbest $w.blundersonly -side top -fill x
  
  frame $w.blunderbox
  pack $w.blunderbox -side top -padx 5 -pady 5
  
  label $w.blunderbox.label -text $::tr(BlundersThreshold:)
  spinbox $w.blunderbox.spBlunder -background white -width 4 -textvariable blunderThreshold \
      -from 0.1 -to 3.0 -increment 0.1
  pack $w.blunderbox.label $w.blunderbox.spBlunder -side left -padx 5 -pady 5
  
  addHorizontalRule $w
  checkbutton $w.cbAnnotateVar  -text $::tr(AnnotateVariations) -variable ::isAnnotateVar -anchor w
  checkbutton $w.cbShortAnnotation  -text $::tr(ShortAnnotations) -variable ::isShortAnnotation -anchor w
  checkbutton $w.cbAddScore  -text $::tr(AddScoreToShortAnnotations) -variable ::addScoreToShortAnnotations -anchor w
  checkbutton $w.cbAddAnnotatorTag  -text $::tr(addAnnotatorTag) -variable ::addAnnotatorTag -anchor w
  pack $w.cbAnnotateVar $w.cbShortAnnotation $w.cbAddScore $w.cbAddAnnotatorTag -anchor w
  
  # choose a book for analysis
  addHorizontalRule $w
  checkbutton $w.cbBook  -text $::tr(UseBook) -variable ::useAnalysisBook
  # load book names
  set bookPath $::scidBooksDir
  ::combobox::combobox $w.comboBooks -editable false -width 12
  set bookList [  lsort -dictionary [ glob -nocomplain -directory $bookPath *.bin ] ]
  foreach file  $bookList {
    $w.comboBooks list insert end [ file tail $file ]
  }
  $w.comboBooks select 0
  pack $w.cbBook $w.comboBooks -side top
  
  addHorizontalRule $w
  
  # batch annotation of consecutive games, and optional opening errors finder
  frame $w.batch
  pack $w.batch -side top -fill x
  set to [sc_base numGames]
  if {$to <1} { set to 1}
  checkbutton $w.batch.cbBatch -text $::tr(AnnotateSeveralGames) -variable ::isBatch
  spinbox $w.batch.spBatchEnd -background white -width 8 -textvariable ::batchEnd \
      -from 1 -to $to -increment 1 -validate all -vcmd { regexp {^[0-9]+$} %P }
  checkbutton $w.batch.cbBatchOpening -text $::tr(FindOpeningErrors) -variable ::isBatchOpening
  spinbox $w.batch.spBatchOpening -background white -width 2 -textvariable ::isBatchOpeningMoves \
      -from 10 -to 20 -increment 1 -validate all -vcmd { regexp {^[0-9]+$} %P }
  label $w.batch.lBatchOpening -text $::tr(moves)
  pack $w.batch.cbBatch $w.batch.spBatchEnd -side top -fill x
  pack $w.batch.cbBatchOpening $w.batch.spBatchOpening $w.batch.lBatchOpening  -side left -fill x
  set ::batchEnd $to
  
  addHorizontalRule $w
  frame $w.buttons
  pack $w.buttons -side top -fill x
  button $w.buttons.cancel -text $::tr(Cancel) -command {
    destroy .configAnnotation
    set annotateMode 0
    set annotateModeButtonValue 0
  }
  button $w.buttons.ok -text "OK" -command {
    set ::useAnalysisBookName [.configAnnotation.comboBooks get]
    set  ::wentOutOfBook 0
    
    if {$tempdelay < 0.1} { set tempdelay 0.1 }
    set autoplayDelay [expr {int($tempdelay * 1000)}]
    destroy .configAnnotation
    set annotateMode 1
    if {! $analysis(analyzeMode1)} {
      toggleEngineAnalysis 1 1
    }
    if {$::addAnnotatorTag} {
      appendAnnotator "$analysis(name1)"
    }
    if {$autoplayMode == 0} {  toggleAutoplay }
  }
  pack $w.buttons.cancel $w.buttons.ok -side right -padx 5 -pady 5
  focus $w.spDelay
  update ; # or grab will fail
  grab $w
  bind $w <Destroy> { focus . }
}
################################################################################
# Part of annotation process : will check the moves if they are in te book, and add a comment
# when going out of it
################################################################################
proc bookAnnotation { {n 1} } {
  global analysis
  
  if {$::annotateMode && $::useAnalysisBook} {
    
    set prevbookmoves ""
    set bn [ file join $::scidBooksDir $::useAnalysisBookName ]
    sc_book load $bn $::analysisBookSlot
    
    set bookmoves [sc_book moves $::analysisBookSlot]
    while {[string length $bookmoves] != 0 && ![sc_pos isAt vend]} {
      # we are in book, so move immediately forward
      ::move::Forward
      set prevbookmoves $bookmoves
      set bookmoves [sc_book moves $::analysisBookSlot]
    }
    sc_book close $::analysisBookSlot
    set ::wentOutOfBook 1
    
    if { [ string match -nocase "*[sc_game info previousMoveNT]*" $prevbookmoves ] != 1 } {
      if {$prevbookmoves != ""} {
        sc_pos setComment "[sc_pos getComment] $::tr(MoveOutOfBook) ($prevbookmoves)"
      } else  {
        sc_pos setComment "[sc_pos getComment] $::tr(MoveOutOfBook)"
      }
    } else  {
      sc_pos setComment "[sc_pos getComment] $::tr(LastBookMove)"
    }
    
    # last move was out of book or the last move in book : it needs to be analyzed, so take back
    if { ![catch { sc_move back 1 } ] } {
      resetAnalysis
      updateBoard -pgn
      for {set i 0} {$i<100} {incr i} { update ; after [expr $::autoplayDelay / 100] }
      set analysis(prevscore$n) $analysis(score$n)
      set analysis(prevmoves$n) $analysis(moves$n)
      updateBoard -pgn
    }
  }
}
################################################################################
#
################################################################################
proc addAnnotation { {n 1} } {
  global analysis annotateMoves annotateBlunders annotateMode blunderThreshold
  
  # First look in the book selected
  if { ! $::wentOutOfBook && $::useAnalysisBook} {
    bookAnnotation
    return
  }
  
  # Cannot add a variation to an empty variation:
  if {[sc_pos isAt vstart]  &&  [sc_pos isAt vend]} { return }
  
  # Cannot (yet) add a variation at the end of the game or a variation:
  if {[sc_pos isAt vend]} { return }
  
  set tomove [sc_pos side]
  if {$annotateMoves == "white"  &&  $tomove == "white" ||
    $annotateMoves == "black"  &&  $tomove == "black" } {
    set analysis(prevscore$n) $analysis(score$n)
    set analysis(prevmoves$n) $analysis(moves$n)
    return
  }
  
  # to parse scores if the engine's name contains - or + chars (see sc_game_scores)
  set engine_name  [string map {"-" " " "+" " "} $analysis(name1)]
  
  set text [format "%d:%+.2f" $analysis(depth$n) $analysis(score$n)]
  set moves $analysis(moves$n)
  # Temporarily clear the pre-move command since we want to add a
  # whole line without Scid updating stuff:
  sc_info preMoveCmd {}
  
  set score $analysis(score$n)
  set prevscore $analysis(prevscore$n)
  
  set deltamove [expr {$score - $prevscore}]
  set isBlunder 0
  if {$annotateBlunders == "blundersonly"} {
    if { $deltamove < [expr 0.0 - $blunderThreshold] && $tomove == "black" || \
          $deltamove > $blunderThreshold && $tomove == "white" } {
      set isBlunder 1
    }
    # if the game is dead, and the score continues to go down, don't add any comment
    if { $prevscore > $::informant("++-") && $tomove == "white" || \
          $prevscore < [expr 0.0 - $::informant("++-") ] && $tomove == "black" } {
      set isBlunder 0
    }
  } elseif {$annotateBlunders == "notbest"} { ; # not best move option
    if { $deltamove < 0.0 && $tomove == "black" || \
          $deltamove > 0.0 && $tomove == "white" } {
      set isBlunder 1
    }
  }
  
  set text [format "%+.2f" $score]
  if {$annotateBlunders == "allmoves"} {
    set absdeltamove [expr { abs($deltamove) } ]
    if { $deltamove < [expr 0.0 - $blunderThreshold] && $tomove == "black" || \
          $deltamove > $blunderThreshold && $tomove == "white" } {
      if {$absdeltamove > $::informant("?!") && $absdeltamove <= $::informant("?")} {
        sc_pos addNag "?!"
      } elseif {$absdeltamove > $::informant("?") && $absdeltamove <= $::informant("??")} {
        sc_pos addNag "?"
      } elseif {$absdeltamove > $::informant("??") } {
        sc_pos addNag "??"
      }
    }
    
    
    if {! $::isShortAnnotation } {
      sc_pos setComment "[sc_pos getComment] $engine_name: $text"
    } else {
      if {$::addScoreToShortAnnotations} {
        sc_pos setComment "[sc_pos getComment] $text"
      }
    }
    
    if {$::isBatchOpening} {
      if { [sc_pos moveNumber] < $::isBatchOpeningMoves} {
        appendAnnotator "opBlunder [sc_pos moveNumber] ([sc_pos side])"
        updateBoard -pgn
      }
    }
    set nag [ scoreToNag $score ]
    if {$nag != ""} {
      sc_pos addNag $nag
    }
    
    sc_move back
    if { $analysis(prevmoves$n) != ""} {
      sc_var create
      set moves $analysis(prevmoves$n)
      sc_move_add $moves $n
      set nag [ scoreToNag $prevscore ]
      if {$nag != ""} {
        sc_pos addNag $nag
      }
      sc_var exit
      sc_move forward
    }
  } elseif { $isBlunder } {
    # Add the comment to highlight the blunder
    set absdeltamove [expr { abs($deltamove) } ]
    
    # if the game was won and the score remains high, don't add comment
    if { $score > $::informant("++-") && $tomove == "black" || \
          $score < [expr 0.0 - $::informant("++-") ] && $tomove == "white" } {
      set text [format "%+.2f (%+.2f)" $prevscore $score]
      if {! $::isShortAnnotation } {
        sc_pos setComment "[sc_pos getComment] $engine_name: $text"
      }  else {
        if {$::addScoreToShortAnnotations} {
          sc_pos setComment "[sc_pos getComment] $text"
        }
      }
    } else  {
      if {$absdeltamove > $::informant("?!") && $absdeltamove <= $::informant("?")} {
        sc_pos addNag "?!"
      } elseif {$absdeltamove > $::informant("?") && $absdeltamove <= $::informant("??")} {
        sc_pos addNag "?"
      } elseif {$absdeltamove > $::informant("??") } {
        sc_pos addNag "??"
      }
      
      set text [format "%s %+.2f / %+.2f" $::tr(AnnotateBlundersOnlyScoreChange) $prevscore $score]
      if {! $::isShortAnnotation } {
        sc_pos setComment "[sc_pos getComment] $engine_name: $text"
      } else {
        if {$::addScoreToShortAnnotations} {
          sc_pos setComment "[sc_pos getComment] [format %+.2f $score]"
        }
      }
    }
    
    if {$::isBatchOpening} {
      if { [sc_pos moveNumber] < $::isBatchOpeningMoves} {
        appendAnnotator "opBlunder [sc_pos moveNumber] ([sc_pos side])"
        updateBoard -pgn
      }
    }
    set nag [ scoreToNag $score ]
    if {$nag != ""} {
      sc_pos addNag $nag
    }
    # Rewind, request a diagram
    sc_move back
    sc_pos addNag "D"
    
    # Add the variation:
    if { $analysis(prevmoves$n) != ""} {
      sc_var create
      set moves $analysis(prevmoves$n)
      # Add as many moves as possible from the engine analysis:
      sc_move_add $moves $n
      set nag [ scoreToNag $prevscore ]
      if {$nag != ""} {
        sc_pos addNag $nag
      }
      sc_var exit
      sc_move forward
    }
  }
  
  set analysis(prevscore$n) $analysis(score$n)
  set analysis(prevmoves$n) $analysis(moves$n)
  
  # Restore the pre-move command:
  sc_info preMoveCmd preMoveCommand
  updateBoard -pgn
  # Update score graph if it is open:
  if {[winfo exists .sgraph]} { ::tools::graphs::score::Refresh }
}
################################################################################
#
################################################################################
proc scoreToNag {score} {
  if {$score >= $::informant("+-")} {
    return "+-"
  }
  if {$score >= $::informant("+/-")} {
    return "+/-"
  }
  if {$score >= $::informant("+=")} {
    return "+="
  }
  if { $score >= [expr 0.0 - $::informant("+=") ]} {
    return "="
  }
  if {$score <= [expr 0.0 - $::informant("+-") ]} {
    return "-+"
  }
  if {$score <= [expr 0.0 - $::informant("+/-") ]} {
    return "-/+"
  }
  if {$score <= [expr 0.0 - $::informant("+=") ]} {
    return "-="
  }
}
################################################################################
# will append arg to current game Annotator tag
################################################################################
proc appendAnnotator { s } {
  set extra [sc_game tags get "Extra"]
  # find Annotator tag
  set oldAnn ""
  set found 0
  foreach line $extra {
    if {$found} {
      set oldAnn $line
      break
    }
    if {[string match "Annotator" $line]} {
      set found 1
      continue
    }
  }
  
  if {$oldAnn != ""} {
    set ann "Annotator \"$oldAnn $s\"\n"
  } else  {
    set ann "Annotator \"$s\"\n"
  }
  sc_game tags set -extra [ list $ann ]
}
################################################################################
#
################################################################################
proc pushAnalysisData { { lastVar } { n 1 } } {
  global analysis
  lappend ::stack [list $analysis(prevscore$n) $analysis(score$n) \
      $analysis(prevmoves$n) $analysis(moves$n) $lastVar ]
}
################################################################################
#
################################################################################
proc popAnalysisData { { n 1 } } {
  global analysis
  # the start of analysis is in the middle of a variation
  if {[llength $::stack] == 0} {
    set analysis(prevscore$n) 0
    set analysis(score$n) 0
    set analysis(prevmoves$n) ""
    set analysis(moves$n) ""
    set lastVar 0
    return
  }
  set tmp [lindex $::stack end]
  set analysis(prevscore$n) [lindex $tmp 0]
  set analysis(score$n) [lindex $tmp 1]
  set analysis(prevmoves$n) [lindex $tmp 2]
  set analysis(moves$n) [lindex $tmp 3]
  set lastVar [lindex $tmp 4]
  set ::stack [lreplace $::stack end end]
  return $lastVar
}

################################################################################
#
################################################################################
proc addAnalysisVariation {{n 1}} {
  global analysis
  
  if {! [winfo exists .analysisWin$n]} { return }
  
  # Cannot add a variation to an empty variation:
  if {[sc_pos isAt vstart]  &&  [sc_pos isAt vend]} { return }
  # Cannot (yet) add a variation at the end of the game or a variation:
  if {[sc_pos isAt vend]} { return }
  
  set text [format "%d:%+.2f" $analysis(depth$n) $analysis(score$n)]
  set moves $analysis(moves$n)
  # Temporarily clear the pre-move command since we want to add a
  # whole line without Scid updating stuff:
  sc_info preMoveCmd {}
  
  # Add the variation:
  sc_var create
  # Add the comment at the start of the variation:
  sc_pos setComment "[sc_pos getComment] $text"
  # Add as many moves as possible from the engine analysis:
  sc_move_add $moves $n
  sc_var exit
  
  # Restore the pre-move command:
  sc_info preMoveCmd preMoveCommand
  updateBoard -pgn
  # Update score graph if it is open:
  if {[winfo exists .sgraph]} { ::tools::graphs::score::Refresh }
}
################################################################################
#
################################################################################
# TODO fonction obsolète à virer ??
proc addAnalysisToComment {line {n 1}} {
  global analysis
  if {! [winfo exists .analysisWin$n]} { return }
  
  # If comment editor window is open, add the score there, otherwise
  # just add the comment directly:
  if {[winfo exists .commentWin]} {
    set tempStr [.commentWin.cf.text get 1.0 "end-1c"]
  } else {
    set tempStr [sc_pos getComment]
  }
  set score $analysis(score$n)
  
  # If line is true, add the whole line, else just add the score:
  if {$line} {
    set scoretext [format "%+.2f: %s" $score $analysis(moves$n)]
  } else {
    set scoretext [format "%+.2f" $score]
  }
  
  # Strip out old score if it exists at the start of the comment:
  regsub {^\".*\"} $tempStr "" tempStr
  set newText "\"$scoretext\"$tempStr"
  if {[winfo exists .commentWin]} {
    .commentWin.cf.text delete 1.0 end
    .commentWin.cf.text insert 1.0 $newText
  } else {
    sc_pos setComment $newText
  }
  ::pgn::Refresh 1
}
################################################################################
#
################################################################################
proc makeAnalysisMove {{n 1}} {
  set s $::analysis(moves$n)
  set res 1
  while {1} {
    if {[string length $s] == 0} { return 0 }
    set c [string index $s 0]
    switch -- $c {
      a - b - c - d - e - f - g - h -
      K - Q - R - B - N - O {
        break
      }
    }
    set s [string range $s 1 end]
  }
  if {[scan $s "%s" move] != 1} { set res 0 }
  set action "replace"
  if {! [sc_pos isAt vend]} {
    set action [confirmReplaceMove]
  }
  if {$action == "cancel"} { return }
  set ::analysis(automoveThinking$n) 0
  if {$action == "var"} { sc_var create }
  if { [sc_move_add $move $n] } { puts "erreur de sc_move_add" ; set res 0 }
  
  updateBoard -pgn -animate
  ::utils::sound::AnnounceNewMove $move
  return $res
}
################################################################################
#
################################################################################

# destroyAnalysisWin:
#   Closes an engine, because its analysis window is being destroyed.
#
proc destroyAnalysisWin {{n 1}} {
  
  global windowsOS analysis annotateModeButtonValue
  
  if { $annotateModeButtonValue } { ; # end annotation
    set annotateModeButtonValue 0
    toggleAutoplay
  }
  
  # Check the pipe is not already closed:
  if {$analysis(pipe$n) == ""} {
    set ::analysisWin$n 0
    return
  }
  
  # Send interrupt signal if the engine wants it:
  if {(!$windowsOS)  &&  $analysis(send_sigint$n)} {
    catch {exec -- kill -s INT [pid $analysis(pipe$n)]}
  }
  
  # Some engines in analyze mode may not react as expected to "quit"
  # so ensure the engine exits analyze mode first:
  if {$analysis(uci$n)} {
    sendToEngine $n "stop"
    sendToEngine $n "quit"
  } else  {
    sendToEngine $n "exit"
    sendToEngine $n "quit"
  }
  catch { flush $analysis(pipe$n) }
  
  # Uncomment the following line to turn on blocking mode before
  # closing the engine (but probably not a good idea!)
  #   fconfigure $analysis(pipe$n) -blocking 1
  
  # Close the engine, ignoring any errors since nothing can really
  # be done about them anyway -- maybe should alert the user with
  # a message box?
  catch {close $analysis(pipe$n)}
  
  if {$analysis(log$n) != ""} {
    catch {close $analysis(log$n)}
    set analysis(log$n) ""
  }
  set analysis(pipe$n) ""
  set ::analysisWin$n 0
}

# sendToEngine:
#   Send a command to a running analysis engine.
#
proc sendToEngine {n text} {
  logEngine $n "Scid  : $text"
  catch {puts $::analysis(pipe$n) $text}
}

# sendMoveToEngine:
#   Sends a move to a running analysis engine, using sendToEngine.
#   If the engine has indicated (with "usermove=1" on a "feature" line)
#   that it wants it, send with "usermove " before the move.
#
proc sendMoveToEngine {n move} {
  # Convert "e7e8Q" into "e7e8q" since that is the XBoard/WinBoard
  # standard for sending moves in coordinate notation:
  set move [string tolower $move]
  if {$::analysis(uci$n)} {
    # should be position fen [sc_pos fen] moves ?
    sendToEngine $n "position fen [sc_pos fen] moves $move"
  } else  {
    if {$::analysis(wants_usermove$n)} {
      sendToEngine $n "usermove $move"
    } else {
      sendToEngine $n $move
    }
  }
}

# logEngine:
#   Log Scid-Engine communication.
#
proc logEngine {n text} {
  global analysis
  
  # Print the log message to stdout if applicable:
  if {$::analysis(log_stdout)} {
    puts stdout $text
  }
  
  if { [ info exists ::analysis(log$n)] && $::analysis(log$n) != ""} {
    puts $::analysis(log$n) $text
    
    # Close the log file if the limit is reached:
    incr analysis(logCount$n)
    if {$analysis(logCount$n) >= $analysis(logMax)} {
      puts $::analysis(log$n) \
          "NOTE  : Log file size limit reached; closing log file."
      catch {close $analysis(log$n)}
      set analysis(log$n) ""
    }
  }
}

# logEngineNote:
#   Add a note to the engine comminucation log file.
#
proc logEngineNote {n text} {
  logEngine $n "NOTE  : $text"
}

################################################################################
#
# makeAnalysisWin:
#   Produces the engine list dialog box for choosing an engine,
#   then opens an analysis window and starts the engine.
################################################################################
proc makeAnalysisWin { {n 1} {index -1} } {
  global analysisWin$n font_Analysis analysisCommand analysis annotateModeButtonValue
  set w ".analysisWin$n"
  if {[winfo exists $w]} {
    focus .
    destroy $w
    set analysisWin$n 0
    resetEngine $n
    return
  }
  
  if {$n == 1} { set annotateModeButtonValue 0 }
  
  resetEngine $n
  
  #Klimmek: if parameter index is a valid engine then start engine
  if { $index < 0 } {
    set index [::enginelist::choose]
  } else {
    set index [expr {$n - 1}]
  }
  
  if {$index == ""  ||  $index < 0} {
    set analysisWin$n 0
    return
  }
  ::enginelist::setTime $index
  catch {::enginelist::write}
  set analysis(index$n) $index
  set engineData [lindex $::engines(list) $index]
  set analysisName [lindex $engineData 0]
  set analysisCommand [ toAbsPath [lindex $engineData 1] ]
  set analysisArgs [lindex $engineData 2]
  set analysisDir [ toAbsPath [lindex $engineData 3] ]
  set analysis(uci$n) [ lindex $engineData 7 ]
  
  # If the analysis directory is not current dir, cd to it:
  set oldpwd ""
  if {$analysisDir != "."} {
    set oldpwd [pwd]
    catch {cd $analysisDir}
  }
  
  if {! $analysis(uci$n) } {
    set analysis(multiPVCount$n) 1
  }
  
  # Try to execute the analysis program:
  if {[catch {set analysis(pipe$n) [open "| [list $analysisCommand] $analysisArgs" "r+"]} result]} {
    if {$oldpwd != ""} { catch {cd $oldpwd} }
    tk_messageBox -title "Scid: error starting analysis" \
        -icon warning -type ok \
        -message "Unable to start the program:\n$analysisCommand"
    set analysisWin$n 0
    resetEngine $n
    return
  }
  
  set analysisWin$n 1
  
  # Return to original dir if necessary:
  if {$oldpwd != ""} { catch {cd $oldpwd} }
  
  # Open log file if applicable:
  set analysis(log$n) ""
  if {$analysis(logMax) > 0} {
    if {! [catch {open [file join $::scidLogDir "engine$n.log"] w} log]} {
      set analysis(log$n) $log
      logEngine $n "Scid-Engine communication log file"
      logEngine $n "Engine: $analysisName"
      logEngine $n "Command: $analysisCommand"
      logEngine $n "Date: [clock format [clock seconds]]"
      logEngine $n ""
      logEngine $n "This file was automatically generated by Scid."
      logEngine $n "It is rewritten every time an engine is started in Scid."
      logEngine $n ""
    }
  }
  
  set analysis(name$n) $analysisName
  
  # Configure pipe for line buffering and non-blocking mode:
  fconfigure $analysis(pipe$n) -buffering line -blocking 0
  
  #
  # Set up the  analysis window:
  #
  toplevel $w
  if {$n == 1} {
    wm title $w "Scid: Analysis: $analysisName"
  } else {
    wm title $w "Scid: Analysis $n: $analysisName"
  }
  bind $w <F1> { helpWindow Analysis }
  setWinLocation $w
  setWinSize $w
  standardShortcuts $w
  
  ::board::new $w.bd 25
  $w.bd configure -relief solid -borderwidth 1
  set analysis(showBoard$n) 0
  
  frame $w.b1
  pack $w.b1 -side bottom -fill x
  
  checkbutton $w.b1.automove -image tb_training  -indicatoron false -height 24 -relief raised -command "toggleAutomove $n" -variable analysis(automove$n)
  ::utils::tooltip::Set $w.b1.automove $::tr(Training)
  
  button $w.b1.line -image tb_addvar -height 24 -width 24 -command "addAnalysisVariation $n"
  ::utils::tooltip::Set $w.b1.line $::tr(AddVariation)
  
  button $w.b1.move -image tb_addmove -command "makeAnalysisMove $n"
  ::utils::tooltip::Set $w.b1.move $::tr(AddMove)
  
  if {$analysis(uci$n)} {
    set state readonly
  } else  {
    set state disabled
  }
  
  spinbox $w.b1.multipv -from 1 -to 8 -increment 1 -textvariable analysis(multiPVCount$n) -state $state -width 2 \
      -command "changePVSize $n"
  ::utils::tooltip::Set $w.b1.multipv $::tr(Lines)
  
  # add a button to start/stop engine analysis
  button $w.b1.bStartStop -image tb_pause -command "toggleEngineAnalysis $n" -relief flat
  ::utils::tooltip::Set $w.b1.bStartStop "$::tr(StopEngine)(a)"
  
  if {$n == 1} {
    set ::finishGameMode 0
    button $w.b1.bFinishGame -image finish_off -command "toggleFinishGame $n" -relief flat
    ::utils::tooltip::Set $w.b1.bFinishGame $::tr(FinishGame)
  }
  button $w.b1.showboard -image tb_coords -height 24 -width 24 -command "toggleAnalysisBoard $n"
  ::utils::tooltip::Set $w.b1.showboard $::tr(ShowAnalysisBoard)
  if {$n == 1} {
    checkbutton $w.b1.annotate -image tb_annotate -indicatoron false -height 24 -variable annotateModeButtonValue -relief raised -command { configAnnotation }
    ::utils::tooltip::Set $w.b1.annotate $::tr(Annotate...)
  }
  checkbutton $w.b1.priority -image tb_cpu -indicatoron false -relief raised -variable analysis(priority$n) -onvalue idle -offvalue normal \
      -command "setAnalysisPriority $n"
  ::utils::tooltip::Set $w.b1.priority $::tr(LowPriority)
  
  if {$analysis(uci$n)} {
    set state disabled
  } else  {
    set state normal
  }
  
  button $w.b1.update -image tb_update -state $state -command "if {$analysis(uci$n)} {sendToEngine $n .}" ;# UCI does not support . command
  ::utils::tooltip::Set $w.b1.update $::tr(Update)
  
  button $w.b1.help -image tb_help -height 24 -width 24 -command { helpWindow Analysis }
  ::utils::tooltip::Set $w.b1.help $::tr(Help)
  
  if {$n ==1} {
    pack $w.b1.bStartStop $w.b1.move $w.b1.line $w.b1.multipv $w.b1.annotate $w.b1.automove $w.b1.bFinishGame -side left
  } else  {
    pack $w.b1.bStartStop $w.b1.move $w.b1.line $w.b1.multipv $w.b1.automove -side left
  }
  pack $w.b1.showboard $w.b1.help $w.b1.update $w.b1.priority -side right
  if {$analysis(uci$n)} {
    text $w.text -width 60 -height 1 -fg black -bg white -font font_Small -wrap word -setgrid 1
  } else {
    text $w.text -width 60 -height 4 -fg black -bg white -font font_Fixed -wrap word -setgrid 1
  }
  frame $w.hist
  text $w.hist.text -width 60 -height 8 -fg black -bg white -font font_Fixed \
      -wrap word -setgrid 1 -yscrollcommand "$w.hist.ybar set"
  $w.hist.text tag configure indent -lmargin2 [font measure font_Fixed "xxxxxxxxxxxx"]
  scrollbar $w.hist.ybar -command "$w.hist.text yview" -takefocus 0
  pack $w.text -side top -fill both
  pack $w.hist -side top -expand 1 -fill both
  pack $w.hist.ybar -side right -fill y
  pack $w.hist.text -side left -expand 1 -fill both
  
  bind $w.hist.text <ButtonPress-3> "toggleMovesDisplay $n"
  $w.text tag configure blue -foreground blue
  $w.text tag configure bold -font font_Bold
  $w.hist.text tag configure blue -foreground blue -lmargin2 [font measure font_Fixed "xxxxxxxxxxxx"]
  $w.hist.text tag configure gray -foreground gray
  $w.text insert end "Please wait a few seconds for engine initialisation (with some engines, you will not see any analysis \
      until the board changes. So if you see this message, try changing the board \
      by moving backward or forward or making a new move.)"
  $w.text configure -state disabled
  bind $w <Destroy> "destroyAnalysisWin $n"
  bind $w <Configure> "recordWinSize $w"
  bind $w <Escape> "focus .; destroy $w"
  bind $w <Key-a> "$w.b1.bStartStop invoke"
  wm minsize $w 25 0
  bindMouseWheel $w $w.hist.text
  
  if {$analysis(uci$n)} {
    fileevent $analysis(pipe$n) readable "::uci::processAnalysisInput $n"
  } else  {
    fileevent $analysis(pipe$n) readable "processAnalysisInput $n"
  }
  after 1000 "checkAnalysisStarted $n"
  
  # finish MultiPV spinbox configuration
  if {$analysis(uci$n)} {
    # find UCI engine MultiPV capability
    while { ! $analysis(uciok$n) } { ;# done after uciok
      update
      after 200
    }
    set hasMultiPV 0
    foreach opt $analysis(uciOptions$n) {
      if { [lindex $opt 0] == "MultiPV" } {
        set hasMultiPV 1
        set min [lindex $opt 1]
        set max [lindex $opt 2]
        if {$min == ""} { set min 1}
        if {$max == ""} { set max 8}
        break
      }
    }
    set current -1
    set options  [ lindex $engineData 8 ]
    foreach opt $options {
      if {[lindex $opt 0] == "MultiPV"} { set current [lindex $opt 1] ; break }
    }
    if {$current == -1} { set current 1 }
    set analysis(multiPVCount$n) $current
    changePVSize $n
    if { $hasMultiPV } {
      $w.b1.multipv configure -from $min -to $max -state readonly
    } else  {
      $w.b1.multipv configure -from 1 -to 1 -state disabled
    }
  } ;# end of MultiPV spinbox configuration
  
  # We hope the engine is correctly started at that point, so we can send the first analyze command
  # this problem only happens with winboard engine, as we don't know when they are ready
  if { !$analysis(uci$n) } {
    initialAnalysisStart $n
  }
  # necessary on windows because the UI sometimes starves, also keep latest priority setting
  if {$::windowsOS || $analysis(priority$n) == "idle"} {
    set analysis(priority$n) idle
    setAnalysisPriority $n
  }
 
}
################################################################################
#
################################################################################
proc toggleMovesDisplay { {n 1} } {
  set ::analysis(movesDisplay$n) [expr 1 - $::analysis(movesDisplay$n)]
  set h .analysisWin$n.hist.text
  $h configure -state normal
  $h delete 1.0 end
  $h configure -state disabled
  updateAnalysisText $n
}

################################################################################
# will truncate PV list if necessary and tell the engine to send N best lines
################################################################################
proc changePVSize { n } {
  global analysis
  if { $analysis(multiPVCount$n) < [llength $analysis(multiPV$n)] } {
    set analysis(multiPV$n) {}
    set ::uci::uciInfo(pvlist$n) {}
  }
  if { $analysis(uci$n) } {
    # if the UCI engine was analysing, we have to stop/restart it to take into acount the new multiPV option
    if {$analysis(analyzeMode$n)} {
      sendToEngine $n "stop"
      set analysis(waitForBestMove$n) 1
      vwait analysis(waitForBestMove$n)
      sendToEngine $n "setoption name MultiPV value $analysis(multiPVCount$n)"
      sendToEngine $n "position fen [sc_pos fen]"
      sendToEngine $n "go infinite ponder"
    } else  {
      sendToEngine $n "setoption name MultiPV value $analysis(multiPVCount$n)"
    }
  }
}
################################################################################
# setAnalysisPriority
#   Sets the priority class (in Windows) or nice level (in Unix)
#   of a running analysis engine.
################################################################################
proc setAnalysisPriority {n} {
  global analysis
  
  # Get the process ID of the analysis engine:
  if {$analysis(pipe$n) == ""} { return }
  set pidlist [pid $analysis(pipe$n)]
  if {[llength $pidlist] < 1} { return }
  set pid [lindex $pidlist 0]
  
  # Set the priority class (idle or normal):
  if {$::windowsOS} {
    catch {sc_info priority $pid $analysis(priority$n)}
  } else {
    set priority 0
    if {$analysis(priority$n) == "idle"} { set priority 15 }
    catch {sc_info priority $pid $priority}
  }
  
  # Re-read the priority class for confirmation:
  if {[catch {sc_info priority $pid} newpriority]} { return }
  if {$::windowsOS} {
    if {$newpriority == "idle"  ||  $newpriority == "normal"} {
      set analysis(priority$n) $newpriority
    }
  } else {
    set priority normal
    if {$newpriority > 0} { set priority idle }
    set analysis(priority$n) $priority
  }
}
################################################################################
# checkAnalysisStarted
#   Called a short time after an analysis engine was started
#   to send it commands if Scid has not seen any output from
#   it yet.
################################################################################
proc checkAnalysisStarted {n} {
  global analysis
  if {$analysis(seen$n)} { return }
  # Some Winboard engines do not issue any output when
  # they start up, so the fileevent above is never triggered.
  # Most, but not all, of these engines will respond in some
  # way once they have received input of some type.  This
  # proc will issue the same initialization commands as
  # those in processAnalysisInput below, but without the need
  # for a triggering fileevent to occur.
  
  logEngineNote $n {Quiet engine (still no output); sending it initial commands.}
  # set analysis(seen$n) 1
  
  if {$analysis(uci$n)} {
    # in order to get options
    sendToEngine $n "uci"
    # egine should respond uciok
    sendToEngine $n "isready"
  } else  {
    sendToEngine $n "xboard"
    sendToEngine $n "protover 2"
    sendToEngine $n "ponder off"
    sendToEngine $n "post"
    # Prevent some engines from making an immediate "book"
    # reply move as black when position is sent later:
    sendToEngine $n "force"
  }
}
################################################################################
# with wb engines, we don't know when the startup phase is over and when the
# engine is ready : so wait for the end of initial output and take some margin
# to issue an analyze command
################################################################################
proc initialAnalysisStart {n} {
  global analysis
  
  update
  
  if { $analysis(processInput$n) == 0 } {
    after 500 initialAnalysisStart $n
    return
  }
  set cl [clock clicks -milliseconds]
  if {[expr $cl - $analysis(processInput$n)] < 1000} {
    after 200 initialAnalysisStart $n
    return
  }
  after 200 startAnalyzeMode $n 1
}
################################################################################
# processAnalysisInput (only for win/xboard engines)
#   Called from a fileevent whenever there is a line of input
#   from an analysis engine waiting to be processed.
################################################################################
proc processAnalysisInput {{n 1}} {
  global analysis
  
  # Get one line from the engine:
  set line [gets $analysis(pipe$n)]
  
  # this is only useful at startup but costs less than 10 microseconds
  set analysis(processInput$n) [clock clicks -milliseconds]
  
  logEngine $n "Engine: $line"
  
  if { ! [ checkEngineIsAlive $n ] } { return }
  
  if {! $analysis(seen$n)} {
    set analysis(seen$n) 1
    # First line of output from the program, so send initial commands:
    logEngineNote $n {First line from engine seen; sending it initial commands now.}
    sendToEngine $n "xboard"
    sendToEngine $n "protover 2"
    sendToEngine $n "ponder off"
    sendToEngine $n "post"
  }
  
  # Check for "feature" commands so we can determine if the engine
  # has the setboard and analyze commands:
  #
  if {! [string compare [string range $line 0 6] "feature"]} {
    if {[string match "*analyze=1*" $line]} { set analysis(has_analyze$n) 1 }
    if {[string match "*setboard=1*" $line]} { set analysis(has_setboard$n) 1 }
    if {[string match "*usermove=1*" $line]} { set analysis(wants_usermove$n) 1 }
    if {[string match "*sigint=1*" $line]} { set analysis(send_sigint$n) 1 }
    if {[string match "*myname=*" $line] } {
      if { !$analysis(wbEngineDetected$n) } { detectWBEngine $n $line  }
      if { [regexp "myname=\"(\[^\"\]*)\"" $line dummy name]} {
        if {$n == 1} {
          catch {wm title .analysisWin$n "Scid: Analysis: $name"}
        } else {
          catch {wm title .analysisWin$n "Scid: Analysis $n: $name"}
        }
      }
    }
    return
  }
  
  # Check for a line starting with "Crafty", so Scid can work well
  # with older Crafty versions that do not recognize "protover":
  #
  if {! [string compare [string range $line 0 5] "Crafty"]} {
    logEngineNote $n {Seen "Crafty"; assuming analyze and setboard commands.}
    set major 0
    if {[scan $line "Crafty v%d.%d" major minor] == 2  &&  $major >= 18} {
      logEngineNote $n {Crafty version is >= 18.0; assuming scores are from White perspective.}
      set analysis(invertScore$n) 0
    }
    # Turn off crafty logging, to reduce number of junk files:
    sendToEngine $n "log off"
    # Set a fairly low noise value so Crafty is responsive to board changes,
    # but not so low that we get lots of short-ply search data:
    sendToEngine $n "noise 1000"
    set analysis(isCrafty$n) 1
    set analysis(has_setboard$n) 1
    set analysis(has_analyze$n) 1
    return
  }
  
  # Scan the line from the engine for the analysis data:
  #
  set res [scan $line "%d%c %d %d %s %\[^\n\]\n" \
      temp_depth dummy temp_score \
      temp_time temp_nodes temp_moves]
  if {$res == 6} {
    if {$analysis(invertScore$n)  && (![string compare [sc_pos side] "black"])} {
      set temp_score [expr { 0.0 - $temp_score } ]
    }
    set analysis(depth$n) $temp_depth
    set analysis(score$n) $temp_score
    # Convert score to pawns from centipawns:
    set analysis(score$n) [expr {double($analysis(score$n)) / 100.0} ]
    set analysis(moves$n) [formatAnalysisMoves $temp_moves]
    set analysis(time$n) $temp_time
    set analysis(nodes$n) [calculateNodes $temp_nodes]
    
    # Convert time to seconds from centiseconds:
    if {! $analysis(wholeSeconds$n)} {
      set analysis(time$n) [expr {double($analysis(time$n)) / 100.0} ]
    }
    
    updateAnalysisText $n
    
    if {! $analysis(seenEval$n)} {
      # This is the first evaluation line seen, so send the current
      # position details to the engine:
      set analysis(seenEval$n) 1
    }
    
    return
  }
  
  # Check for a "stat01:" line, the reply to the "." command:
  #
  if {! [string compare [string range $line 0 6] "stat01:"]} {
    if {[scan $line "%s %d %s %d" \
          dummy temp_time temp_nodes temp_depth] == 4} {
      set analysis(depth$n) $temp_depth
      set analysis(time$n) $temp_time
      set analysis(nodes$n) [calculateNodes $temp_nodes]
      # Convert time to seconds from centiseconds:
      if {! $analysis(wholeSeconds$n)} {
        set analysis(time$n) [expr {double($analysis(time$n)) / 100.0} ]
      }
      updateAnalysisText $n
    }
    return
  }
  
  # Check for other engine-specific lines:
  # The following checks are intended to make Scid work with
  # various WinBoard engines that are not properly configured
  # by the "feature" line checking code above.
  #
  # Many thanks to Allen Lake for testing Scid with many
  # WinBoard engines and providing this code and the detection
  # code in wbdetect.tcl
  if { !$analysis(wbEngineDetected$n) } {
    detectWBEngine $n $line
  }
  
}
################################################################################
# returns 0 if engine died abruptly or 1 otherwise
################################################################################
proc checkEngineIsAlive { {n 1} } {
  global analysis
  
  if {[eof $analysis(pipe$n)]} {
    fileevent $analysis(pipe$n) readable {}
    catch {close $analysis(pipe$n)}
    set analysis(pipe$n) ""
    logEngineNote $n {Engine terminated without warning.}
    catch {destroy .analysisWin$n}
    tk_messageBox -type ok -icon info -parent . -title "Scid" \
        -message "The analysis engine terminated without warning; it probably crashed or had an internal error."
    return 0
  }
  return 1
}
################################################################################
# formatAnalysisMoves:
#   Given the text at the end of a line of analysis data from an engine,
#   this proc tries to strip out some extra stuff engines add to make
#   the text more compatible for adding as a variation.
################################################################################
proc formatAnalysisMoves {text} {
  # Yace puts ".", "t", "t-" or "t+" at the start of its moves text,
  # unless directed not to in its .ini file. Get rid of it:
  if {[strIsPrefix ". " $text]} { set text [string range $text 2 end]}
  if {[strIsPrefix "t " $text]} { set text [string range $text 2 end]}
  if {[strIsPrefix "t- " $text]} { set text [string range $text 3 end]}
  if {[strIsPrefix "t+ " $text]} { set text [string range $text 3 end]}
  
  # Trim any initial or final whitespace:
  set text [string trim $text]
  
  # Yace often adds "H" after a move, e.g. "Bc4H". Remove them:
  regsub -all "H " $text " " text
  
  # Crafty adds "<HT>" for a hash table comment. Change it to "{HT}":
  regsub "<HT>" $text "{HT}" text
  
  return $text
}
################################################################################
# will ask engine to play the game till the end
################################################################################
proc toggleFinishGame { { n 1 } } {
  global analysis
  set b ".analysisWin$n.b1.bFinishGame"
  
  if { $::annotateModeButtonValue || $::autoplayMode || !$analysis(analyzeMode$n) || ! [sc_pos isAt vend] } {
    return
  }
  
  if {!$::finishGameMode} {
    set ::finishGameMode 1
    $b configure -image finish_on -relief flat
    after $::autoplayDelay autoplayFinishGame
  } else  {
    set ::finishGameMode 0
    $b configure -image finish_off -relief flat
    after cancel autoplayFinishGame
  }
}
################################################################################
#
################################################################################
proc autoplayFinishGame { {n 1} } {
  if {!$::finishGameMode || ![winfo exists .analysisWin$n]} {return}
  .analysisWin$n.b1.move invoke
  if { [string index [sc_game info previousMove] end] == "#"} {
    toggleFinishGame $n
    return
  }
  after $::autoplayDelay autoplayFinishGame
}
################################################################################
#
################################################################################
proc toggleEngineAnalysis { { n 1 } { force 0 } } {
  global analysis
  set b ".analysisWin$n.b1.bStartStop"
  
  if { $n == 1} {
    if { ($::annotateModeButtonValue || $::finishGameMode) && ! $force } {
      return
    }
  }
  
  if {$analysis(analyzeMode$n)} {
    stopAnalyzeMode $n
    $b configure -image tb_play -relief flat
    ::utils::tooltip::Set $b "$::tr(StartEngine)(a)"
  } else  {
    startAnalyzeMode $n
    $b configure -image tb_pause -relief flat
    ::utils::tooltip::Set $b "$::tr(StopEngine)(a)"
  }
}
################################################################################
# startAnalyzeMode:
#   Put the engine in analyze mode.
################################################################################
proc startAnalyzeMode {{n 1} {force 0}} {
  global analysis
  
  # Check that the engine has not already had analyze mode started:
  if {$analysis(analyzeMode$n) && ! $force } { return }
  set analysis(analyzeMode$n) 1
  if { $analysis(uci$n) } {
    set analysis(waitForReadyOk$n) 1
    sendToEngine $n "isready"
    vwait analysis(waitForReadyOk$n)
    sendToEngine $n "position fen [sc_pos fen]"
    sendToEngine $n "go infinite ponder"
  } else  {
    if {$analysis(has_setboard$n)} {
      sendToEngine $n "setboard [sc_pos fen]"
    }
    if { $analysis(has_analyze$n) } {
      #updateAnalysis $n
      sendToEngine $n "analyze"
    } else  {
      updateAnalysis $n ;# in order to handle special cases (engines without setboard and analyse commands)
    }
  }
}
################################################################################
# stopAnalyzeMode
################################################################################
proc stopAnalyzeMode { {n 1} } {
  global analysis
  if {! $analysis(analyzeMode$n)} { return }
  set analysis(analyzeMode$n) 0
  if { $analysis(uci$n) } {
    sendToEngine $n "stop"
  } else  {
    sendToEngine $n "exit"
  }
}
################################################################################
# updateAnalysisText
#   Update the text in an analysis window.
################################################################################
proc updateAnalysisText {{n 1}} {
  global analysis
  
  set nps 0
  
  if {$analysis(time$n) > 0.0} {
    set nps [expr {round($analysis(nodes$n) / $analysis(time$n))} ]
  }
  set score $analysis(score$n)
  
  set t .analysisWin$n.text
  set h .analysisWin$n.hist.text
  
  $t configure -state normal
  $t delete 0.0 end
  
  if { $analysis(uci$n) } {
    $t insert end "[tr Depth]: " bold
    $t insert end [ format "%2u " $analysis(depth$n) ]
    $t insert end "[tr Nodes]: " bold
    $t insert end [ format "%6uK (%u kn/s) " $analysis(nodes$n) $nps ]
    $t insert end "[tr Time]: " bold
    $t insert end [ format "%6.2f s" $analysis(time$n) ]
  } else {
    set newStr [format "Depth:   %6u      Nodes: %6uK (%u kn/s)\n" $analysis(depth$n) $analysis(nodes$n) $nps]
    append newStr [format "Score: %+8.2f      Time: %9.2f seconds\n" $score $analysis(time$n)]
    $t insert 1.0 $newStr
  }
  
  
  if {$analysis(automove$n)} {
    if {$analysis(automoveThinking$n)} {
      set moves "   Thinking..... "
    } else {
      set moves "   Your move..... "
    }
    
    if { ! $analysis(uci$n) } {
      $t insert end $moves blue
    }
    $t configure -state disabled
    updateAnalysisBoard $n ""
    return
  }
  
  if {! $::analysis(movesDisplay$n)}  {
    $h configure -state normal
    $h delete 0.0 end
    $h insert end "     $::tr(ClickHereToSeeMoves)\n" blue
    updateAnalysisBoard $n ""
    $h configure -state disabled
    return
  }
  
  if { $analysis(uci$n) } {
    set moves [ lindex [ lindex $analysis(multiPV$n) 0 ] 2 ]
  } else  {
    set moves $analysis(moves$n)
  }
  
  $h configure -state normal
  set cleared 0
  if { $analysis(depth$n) < $analysis(prev_depth$n)  || $analysis(prev_depth$n) == 0 } {
    $h delete 1.0 end
    set cleared 1
  }
  
  ################################################################################
  if { $analysis(uci$n) } {
    if {$cleared} { set analysis(multiPV$n) {} }
    $h delete 1.0 end
    # First line
    set pv [lindex $analysis(multiPV$n) 0]
    if { [expr abs($score)] == 327.0 } {
      if { [catch { set newStr [format "M %d " $analysis(scoremate$n)]} ] } {
        set newStr [format "%2d %+5.2f  " [lindex $pv 0] $score ]
      }
    } else {
      catch { set newStr [format "%2d %+5.2f  " [lindex $pv 0] $score ] }
    }
    $h insert end "1 " gray
    append newStr "[::trans [lindex $pv 2]]\n"
    $h insert end $newStr blue
    
    set lineNumber 1
    foreach pv $analysis(multiPV$n) {
      if {$lineNumber == 1} { incr lineNumber ; continue }
      $h insert end "$lineNumber " gray
      $h insert end [format "%2d %+5.2f  %s\n" [lindex $pv 0] [lindex $pv 1] [::trans [lindex $pv 2]] ] indent
      incr lineNumber
    }
    ################################################################################
  } else  {
    # original Scid analysis display
    $h insert end [format "%2d %+5.2f  %s (%.2f)\n" $analysis(depth$n) $score [::trans $moves] $analysis(time$n)] indent
    $h see end-1c
  }
  
  $h configure -state disabled
  set analysis(prev_depth$n) $analysis(depth$n)
  if { ! $analysis(uci$n) } {
    $t insert end [::trans $moves] blue
  }
  # $t tag add score 2.0 2.13
  $t configure -state disabled
  
  updateAnalysisBoard $n $analysis(moves$n)
}
################################################################################
# toggleAnalysisBoard
#   Toggle whether the small analysis board is shown.
################################################################################
proc toggleAnalysisBoard {n} {
  global analysis
  if { $analysis(showBoard$n) } {
    set analysis(showBoard$n) 0
    pack forget .analysisWin$n.bd
    setWinSize .analysisWin$n
    bind .analysisWin$n <Configure> "recordWinSize .analysisWin$n"
  } else {
    bind .analysisWin$n <Configure> ""
    set analysis(showBoard$n) 1
    pack .analysisWin$n.bd -side right -before .analysisWin$n.b1 -padx 4 -pady 4 -anchor n
    update
    .analysisWin$n.hist.text configure -setgrid 0
    .analysisWin$n.text configure -setgrid 0    
    set x [winfo reqwidth .analysisWin$n]
    set y [winfo reqheight .analysisWin$n]
    wm geometry .analysisWin$n ${x}x${y}
    .analysisWin$n.hist.text configure -setgrid 1
    .analysisWin$n.text configure -setgrid 1    
  }
}
################################################################################
#
################################################################################
# updateAnalysisBoard
#   Update the small analysis board in the analysis window,
#   showing the position after making the specified moves
#   from the current main board position.
#
proc updateAnalysisBoard {n moves} {
  global analysis
  # PG : this should not be commented
  if {! $analysis(showBoard$n)} { return }
  
  set bd .analysisWin$n.bd
  # Temporarily wipe the premove command:
  sc_info preMoveCmd {}
  # Push a temporary copy of the current game:
  sc_game push copy
  
  # Make the engine moves and update the board:
  sc_move_add $moves $n
  ::board::update $bd [sc_pos board]
  
  # Pop the temporary game:
  sc_game pop
  # Restore pre-move command:
  sc_info preMoveCmd preMoveCommand
}
################################################################################
# updateAnalysis
#   Update an analysis window by sending the current board
#   to the engine.
################################################################################
proc updateAnalysis {{n 1}} {
  global analysisWin analysis windowsOS
  if {$analysis(pipe$n) == ""} { return }
  
  # Just return if no output has been seen from the analysis program yet:
  if {! $analysis(seen$n)} { return }
  
  # No need to update if no analysis is running
  if { ! $analysis(analyzeMode$n) } { return }
  
  # If too close to the previous update, and no other future update is
  # pending, reschedule this update to occur in another 0.3 seconds:
  #
  if {[catch {set clicks [clock clicks -milliseconds]}]} {
    set clicks [clock clicks]
  }
  set diff [expr {$clicks - $analysis(lastClicks$n)} ]
  if {$diff < 300  &&  $diff >= 0} {
    if {$analysis(after$n) == ""} {
      set analysis(after$n) [after 300 updateAnalysis $n]
    }
    return
  }
  set analysis(lastClicks$n) $clicks
  set analysis(after$n) ""
  after cancel updateAnalysis $n
  
  set old_movelist $analysis(movelist$n)
  set movelist [sc_game moves coord list]
  set analysis(movelist$n) $movelist
  set nonStdStart [sc_game startBoard]
  set old_nonStdStart $analysis(nonStdStart$n)
  set analysis(nonStdStart$n) $nonStdStart
  
  if { $analysis(uci$n) } {
    sendToEngine $n "stop"
    set analysis(waitForBestMove$n) 1
    vwait analysis(waitForBestMove$n)
    sendToEngine $n "position fen [sc_pos fen]"
    sendToEngine $n "go ponder infinite"
  } else {
    # This section is for engines that support "analyze":
    if {$analysis(has_analyze$n)} {
      sendToEngine $n "exit"   ;# Get out of analyze mode, to send moves.
      
      # On Crafty, "force" command has different meaning when not in
      # XBoard mode, and some users have noticed Crafty not being in
      # that mode at this point -- although I cannot reproduce this.
      # So just re-send "xboard" to Crafty to make sure:
      if {$analysis(isCrafty$n)} { sendToEngine $n "xboard" }
      
      sendToEngine $n "force"  ;# Stop engine replying to moves.
      # Check if the setboard command must be used -- that is, if the
      # previous or current position arose from a non-standard start.
      
      #if {$analysis(has_setboard$n)  &&  ($old_nonStdStart  || $nonStdStart)}
      # We skip all code below if the engine has setboard capability : this is provides less error prone behavior
      if {$analysis(has_setboard$n)} {
        sendToEngine $n "setboard [sc_pos fen]"
        # Most engines with setboard do not recognize the crafty "mn"
        # command (it is not in the XBoard/WinBoard protocol), so only send it to crafty:
        if {$analysis(isCrafty$n)} { sendToEngine $n "mn [sc_pos moveNumber]" }
        sendToEngine $n "analyze"
        return
      }
      
      # If we need a non-standard start and the engine does not have
      # setboard, the user is out of luck:
      if {$nonStdStart} {
        set analysis(moves$n) "  Sorry, this game has a non-standard start position."
        updateAnalysisText $n
        return
      }
      
      # Here, the engine has the analyze command (and no setboard) but this game does
      # not have a non-standard start position.
      
      set oldlen [llength $old_movelist]
      set newlen [llength $movelist]
      
      # Check for optimization to minimize the commands to be sent:
      # Scid sends "undo" to backup wherever possible, and avoid "new" as
      # on many engines this would clear hash tables, causing poor
      # hash table performance.
      
      # Send just the new move if possible (if the new move list is exactly
      # the same as the previous move list, with one extra move):
      if {($newlen == $oldlen + 1) && ($old_movelist == [lrange $movelist 0 [expr {$oldlen - 1} ]])} {
        sendMoveToEngine $n [lindex $movelist $oldlen]
        
      } elseif {($newlen + 1 == $oldlen) && ($movelist == [lrange $old_movelist 0 [expr {$newlen - 1} ]])} {
        # Here the new move list is the same as the old list but with one
        # less move, just send one "undo":
        sendToEngine $n "undo"
        
      } elseif {$newlen == $oldlen  &&  $old_movelist == $movelist} {
        
        # Here the board has not changed, so send nothing
        
      } else {
        
        # Otherwise, undo and re-send all moves:
        for {set i 0} {$i < $oldlen} {incr i} {
          sendToEngine $n "undo"
        }
        foreach m $movelist {
          sendMoveToEngine $n $m
        }
        
      }
      
      sendToEngine $n "analyze"
      
    } else {
      
      # This section is for engines without the analyze command:
      # In this case, Scid just sends "new", "force" and a bunch
      # of moves, then sets a very long search time/depth and
      # sends "go". This is not ideal but it works OK for engines
      # without "analyze" that I have tried.
      
      # If Unix OS and engine wants it, send an INT signal:
      if {(!$windowsOS)  &&  $analysis(send_sigint$n)} {
        catch {exec -- kill -s INT [pid $analysis(pipe$n)]}
      }
      sendToEngine $n "new"
      sendToEngine $n "force"
      if { $nonStdStart && ! $analysis(has_setboard$n) } {
        set analysis(moves$n) "  Sorry, this game has a non-standard start position."
        updateAnalysisText $n
        return
      }
      if {$analysis(has_setboard$n)} {
        sendToEngine $n "setboard [sc_pos fen]"
      } else  {
        foreach m $movelist {
          sendMoveToEngine $n $m
        }
      }
      # Set engine to be white or black:
      sendToEngine $n [sc_pos side]
      # Set search time and depth to something very large and start search:
      sendToEngine $n "st 120000"
      sendToEngine $n "sd 50"
      sendToEngine $n "post"
      sendToEngine $n "go"
    }
  }
}
################################################################################
#
################################################################################

set temptime 0
trace variable temptime w {::utils::validate::Regexp {^[0-9]*\.?[0-9]*$}}

proc setAutomoveTime {{n 1}} {
  global analysis temptime dialogResult
  set ::tempn $n
  set temptime [expr {$analysis(automoveTime$n) / 1000.0} ]
  set w .apdialog
  toplevel $w
  #wm transient $w .analysisWin
  wm title $w "Scid: Engine thinking time"
  wm resizable $w 0 0
  label $w.label -text "Set the engine thinking time per move in seconds:"
  pack $w.label -side top -pady 5 -padx 5
  entry $w.entry -background white -width 10 -textvariable temptime
  pack $w.entry -side top -pady 5
  bind $w.entry <Escape> { .apdialog.buttons.cancel invoke }
  bind $w.entry <Return> { .apdialog.buttons.ok invoke }
  
  addHorizontalRule $w
  
  set dialogResult ""
  set b [frame $w.buttons]
  pack $b -side top -fill x
  button $b.cancel -text $::tr(Cancel) -command {
    focus .
    catch {grab release .apdialog}
    destroy .apdialog
    focus .
    set dialogResult Cancel
  }
  button $b.ok -text "OK" -command {
    catch {grab release .apdialog}
    if {$temptime < 0.1} { set temptime 0.1 }
    set analysis(automoveTime$tempn) [expr {int($temptime * 1000)} ]
    focus .
    catch {grab release .apdialog}
    destroy .apdialog
    focus .
    set dialogResult OK
  }
  pack $b.cancel $b.ok -side right -padx 5 -pady 5
  focus $w.entry
  update
  catch {grab .apdialog}
  tkwait window .apdialog
  if {$dialogResult != "OK"} {
    return 0
  }
  return 1
}

proc toggleAutomove {{n 1}} {
  global analysis
  if {! $analysis(automove$n)} {
    cancelAutomove $n
  } else {
    set analysis(automove$n) 0
    if {! [setAutomoveTime $n]} {
      return
    }
    set analysis(automove$n) 1
    automove $n
  }
}

proc cancelAutomove {{n 1}} {
  global analysis
  set analysis(automove$n) 0
  after cancel "automove $n"
  after cancel "automove_go $n"
}

proc automove {{n 1}} {
  global analysis autoplayDelay
  if {! $analysis(automove$n)} { return }
  after cancel "automove $n"
  set analysis(automoveThinking$n) 1
  after $analysis(automoveTime$n) "automove_go $n"
}

proc automove_go {{n 1}} {
  global analysis
  if {$analysis(automove$n)} {
    if {[makeAnalysisMove $n]} {
      set analysis(autoMoveThinking$n) 0
      updateBoard -pgn
      after cancel "automove $n"
      ::tree::doTraining $n
    } else {
      after 1000 "automove $n"
    }
  }
}
################################################################################
# If UCI engine, add move through a dedicated function in uci namespace
# returns the error caught by catch
################################################################################
proc sc_move_add { moves n } {
  if { $::analysis(uci$n) } {
    return [::uci::sc_move_add $moves]
  } else  {
    return [ catch { sc_move addSan $moves } ]
  }
}
################################################################################
# append scid directory if path starts with .
################################################################################
proc toAbsPath { path } {
  set new $path
  if {[string index $new 0] == "." } {
    set scidInstallDir [file dirname [info nameofexecutable] ]
    set new [ string replace $new 0 0  $scidInstallDir ]
  }
  return $new
}
################################################################################
#
################################################################################
image create photo tb_cpu -data {
  R0lGODlhGAAYAOeiAAAAAAABAQECAgICAgIDAwUFBQYGBgYHCAgICDE1JzI1JzI2JzM3KDU5
  Kjg8LTk9Ljk9Lzo+MDs/MTtALDxAMj1AMjxCLTxCLj1BMj5CND9FMEJIMkNKM0VMNE5VPFFX
  P1ZfQlheR11mR15TuWBmUGFqSWJoU2FrSmNtS2RtTGNZvGRuTGVvTWVbvWZwTWdxTmddvmlv
  Wml0UGp0UGthwGx2Umx2U2x3Um50YG1jwW14U255U255VG55VW9lwm96VG96VXB7VXB7VnF8
  V3J8WHN5ZnJ9V3J9WHNpxHN+WXR/WnaAXHeBXXl+bHeCXnp/bXlvx3iDX3qAbXuAbnqEYXyB
  b3txyHuFYn2CcHyGY3yGZH1zyX2HZX6HZYGCgYCFdH92yn+JZ4CKaIF4y4GLaYOId4KMa4WO
  boaQcId+zomSc4qTdYuD0IyVd42Vd4+H0pCZe5WUipWVjJKK05KbfpSM1JaO1ZefhJiR1pqT
  152V2KKhmJ+Y2aGa2qOd26af3Kii3a2to6+p4LGs4bax47iz5L29tr245sDAwMTDusXFvMnI
  wMzLw9jSm9nTnNDQx9rTnN7Xn9bVzuLcouTdpOXepOfgpujhpt7e1+nip+rjqODf2uDf3ODg
  3OHg3O3mqu3mq+3mrP//////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  /////////////////////////////////yH5BAEKAP8ALAAAAAAYABgAAAj+AP8JHEiwoMGD
  CBMqRAigoUMABh9K/AdAlMWLoiASBNBD0xFQH4mEoojxosaBAG5UqkHphqUZk0iWzLiRwYIG
  DypEkABhgcySEB0ykFJmyhcpRXDEIEERkdOniIKCytTgyR06a9SYMXNFyU+MQZPocIAFzpks
  YboYCfLjq0mKmjI9qOLGDJdOnjY94uHWYtAhQDBgaSNGCydJjBLpoOilsWMvQT9dotAEjZMo
  mBYp2iPjX4FDhAgVKjRIT9AjQjLgIEMliaFAcuKs+GeAECBAfvTgSRNZrokuSYKw1cHiBO1B
  fvrosWNnS9AlNhiEYLJDRooSIkCAoC2oT546deZwQAnakMEHDx04aLAw4cKGfwi62wH/BsnJ
  8gsS5Few/98BQHiAVwcbNJwkEAAyROICJC84gkIj/wjwR4BzvDFGDgEUBEAQn3Do4Sf/EMAH
  GySCYQUMBlIkkUP/DGAFEj7A0IIKI6S40IoNLaTjjjsGBAA7
}
image create photo tb_training -data {
  R0lGODlhGAAYAOeRAGVlZWpnZWhoaG1pZnZrYm5ubnduZYRtWXxwZ3V1dcRkFnl5eYt3aM5r
  G4GBgZF9bYKCgshwKJd+adBvIdRuHIWFhaF+YoaGhpuBbIiIiNtyHqt/XImJicN6P9J2LNd1
  JoqKiouLi8R+Ro2NjY6OjuR4IeR4IuR5IuV5IsuARJCQkJGRkZKSkq2Lb5SUlKeQfZWVlZaW
  luaCMJeXl8yKVJiYmPGBJpmZmfKCJvOCJ5qampycnNGOWb6Ucp2dnduNTp6enp+fn6CgoKGh
  oaKioqSkpOuSSqWlpaampqenp9+ZYaioqKmpqdidbqqqquyZVqurq7iom6ysrK6urtakfK+v
  r7mtpLCwsLKysrOzs7S0tLa2tre3t7i4uLm5ubq6uru7u9a0mcC8ur6+vsDAwMPDw8TExMfH
  x8jIyMnJycrKyt7GssvLy8zMzM/MyM3Nzc7Ozs/Pz9DQ0NHR0dLS0tTU1NXV1dbW1tfX19jY
  2NzX1NnZ2dra2tvb29zc3N3d3d7e3t/f3+Dg4OHh4eLi4uPj4+Tk5OXl5ebm5ufn5+jo6Onp
  6erq6uvr6+zs7O3t7e7u7v//////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  /////////////////////////////////yH5BAEKAP8ALAAAAAAYABgAAAj+AP8JHEjwnwEG
  AQoqXPhvQI8nRpQ8YEjxXwsZOXKg+IGg4kIeJWzYMPEBg0eFNDSUKKFhgoSTBS14oEChQQoC
  MAtuiKBAxIGcBSu4sVIEaNA4X4gYJegAqZClAgWQafPFi46TBRA5esRVESI+bfrkYXTIUCE/
  CxQyIRRI0CFIf97YsWNmiqFEYvFMURjoD6BBkCDRQUOmyxUodRohynOHDwCCMAz5+UOIK6E0
  Y7hcGZOokSI8d/DcIFhGD5UmaxI5Wo2I0KJGjRb9uXOnjpqBCQyFOYGjAx9BiBitZqSIEB/Q
  durgqSCwCKA8UV6I4UO9+p48eZDX2f70HxDQd5Jl16EzZ44cOHDetGGjJg2aM2ZGCNxBBsyX
  Llu0ZMFyZYoUJ0wsgUQRRAwRRBAcCBSDGVVxkR9/VfjnxBJJHEGgEEEIwZxAOviwgw431DBD
  DC6wsIIKJIwQAggZXFABBI9BJaNHAQEAOw==
}
image create photo tb_addmove -data {
  R0lGODlhGAAYAOfwABSDDhOFDhWEDxGIDBOHDRiEEheFERKJDROKDRCMDBOLDRaNEhOQDROQ
  DhKRDRCTCxGTDCOIHhGVDBCWCw+XChCYCw+ZCg6bChCaCw+bCxSYDg6cChWYDxaYEBSaDhaa
  EBOeDhafEBybFhKiDSiTIx2cFxGmDBKmDRGnDDSRLxGqDCOeHhGrDCSfHiSfHyWeIxCuCxCv
  CyegIg+yCw+zCyqiJQ63CjyaNwy7CQ27Cg28Ci+lKgu+CBC8DAy/CUOZPwrBCAzACTSmLjWm
  MArECAzDCQvECAzECAzECTenMj6iOwvHCDmoNAnJBwvICDqoNjupNgjMBgrLBwrMBwjOBkSm
  QQnQB06hSQjUBkOsPlShTzyyNwfYBkqrRkauQTW6Mk2uS0yxSE6ySk+ySl6oWlGyTEO8QlKz
  TVKzTmWqYVe1U0q+SUy+Sk2+TE+9TVC9Tl64Wlu7WW2vamC5XGW7YXSxcUzOSmPBYWq9ZlTM
  Unu1d22/ambEZWzCan+2fGrHaHDEbXDEbnXCcWvLam3KbHPHcXjEdXrEdnDMcHfIdXrKeHvK
  enfOdH3Le4bKg4nLhpDOjZLPkJLQkJDVjZfRlIzaipTVkpHZj5zTmZnVl5bZlJ7Um47fjJ7V
  m6DVnZPekZvZmZfdlaLWn6LWoKPWoZ/ZnpTikqTXopzdmqTZoqbYpJnhmKfYpaHdn6nZp57h
  nKnap6bdpKvaqKvaqZrmmandp6Phoq3bq6zcqqDlnq/crajhprDcrqTlo7Hdr7LdsKzhq7Pd
  saLpoKnlqLTesrbetKbppbbftK7lrKvoqrjgt6jsp7PlsbrgubrhuLrhubDor63srLziu7Xo
  tLHrsL7ivb/iva7vrrrouLbrtbTus8PkwsTkwrvrurnuuLXytL3uvMDsv7rxusLuwb/xvszo
  y7z0vMfuxsTxw8H0wMnxyMb0xc3xzMv0ytD0z9T01P//////////////////////////////
  /////////////////////////////////yH5BAEKAP8ALAAAAAAYABgAAAj+AP8JHDjQzBo2
  bdy8IciwocBB79y1W5fO3CKHGP8hYqcOHTlx3xpldEjo3Dhw3rRdUzSy4Z9w3bJRi7YsUUuG
  fLBNg5bMmLBCNwneYYZsWK9ctAIFHRgH2C5br1aZ6oPxRbBt1ZwV84WrVqxWqEJ94mQHBw8g
  RJpEoZIADDdrz479ugUrVSlQmi5VytPDR5ElUqxg4bKhizRlxHTNYjWqUyZLkxh9mWEjh98l
  UwRfqCL3lqtTnjBRkgRoywkVMGhU9oHESWYLSnTJUjVqEyVDZ1p4ADHChIoYqi0fcU1hwZw9
  eNBAEaGhuYbdvVkArxzEiJMJA5xr1w4dhXTVOqpvP/h3QIF58wgYcA/xoYEDCBIqYMiQkYBz
  ETJ2kFgqMICGDisMkUUYN/D3DwAcuPCEGHDgcYWBAJSQxBh0GOIIGQYKUIMXcxwCiShyGGiA
  EGXs8QgpzehhYAFMqCFIJLyU44eB/0SQwg9apFFHRgEBADs=
}
image create photo tb_update -data {
  R0lGODlhGAAYAOfCAEm5Sly3Sme+Qmi/Q2a9XnG/RHTAPXLARXPBRnHBTXLCTnzAP2vCY3fD
  QXbDSH3BQHTDT3zBR3DBaXnEQnfESX7CQXLEV3jFSnbFUYDDQnTFWILEO2/GZnjDXoHEQ4PF
  PHbEZonDO4LFRITGPX7FU3zFWnrFYIrEPIPGRXvDbH/GVHvGYYbHPovFPYTHRnbHbn7HXIfI
  P4zGPoXIR3fIb3zIYnrIaY/HN4nGTo3HQIPGYoHGaZDIOIfKSYTHY3nKcYDKXpHJOYvIUH3I
  d5LKOn7JeJfIOoHJcZDKQ4jKX5PLPIbKZY3KUoTKbJjJO5XMNIjIcZDLTJTMPYXLbYnJcpjK
  RJzLNJXNPprLPZHNTZ3MNYjLe57NNp/ON4rNfYjNg43Nd6DPOaLQMKXNOI7LgqfOL47OeKbO
  OZHMfajPMKfPOqnQMpPOf6rRM6fQRK3SKazSNJPQh5DTgrHRNbTSK6/VLLLSNrXTLa7VN5XT
  ibTTN53Td7bULrfVL7vTL5rTkbzUMKnTbJbWk7jXMZ3WgL7VMcDWJ7fXO7nYMp/VjZ3Vk7/W
  MsHXKLjYPJ7WlMDXNKTXiMHYNcPZK8XbH7/cLKDYlr7YRsnYLL3YTr/ZR6bXlsPbOKrYkcnZ
  OMvaL6bbk8HbSsfdL63ZjKvZks7cJczbMMvbO83cMcXdQ8feO7Lbh8beRdDfKM7eM7PciK/a
  oM3ePbnaibjdfdXdNdHgNdbeNq/dqtXeQNHhQb7ehbzejNniQ7nfrdvjO9jiTNrjRdvkRuTm
  Sv//////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////
  /////////////////////////////////yH+FUNyZWF0ZWQgd2l0aCBUaGUgR0lNUAAh+QQB
  CgD/ACwAAAAAGAAYAAAI/gD/CRxIsKDBgwSLNGEiRBBChENWRMEELBgoCQ8J/jARJZOvXaYe
  dQLFIKNAEpaC3erkZ5CfQ49MBRj4goQGgzbc3HrUBxGfPn4erQIgkEwjXLd6OCoYB4epTnai
  3rFkioNAGLf4WGo1w6AgLKb8RLVDxxQagVNm+XlDdUXBJqHw2Hn0SK4pMwJfeWhFZ26Ygkge
  tWlTatCsQaWODNRU5dEcO546DLRRx8+cR1WOSCFVSwdBKpTsqOnkYSCNR2fGkCrxT5GKNzsI
  yhEzZ86gGAPNMBrDhVFsgVQUFXxiZ8ygJwO9+MGC5ZLih07aYJmDZCCBOm5u9Lnw8EsbLUro
  mZQeGMRKDixjUiDE4CdHjjmsB0KY02LEmg1sDO4QEySEkTBeEJSCEjlsgEMYOYBAhkBbQBCG
  ERlEEUYEBpXAxQYZZBAEF0GgMAJ6IiwwQRUfQHEQCVZkUIADEUzwgQgqGpBEILIId9ArCRgR
  QgE8FiAACTrsEUssvJjUgQM5nJBBEnuIokssoxRpEoNgQMKJKJzYYsuUXBoUEAA7
}
image create photo tb_annotate -data {
  R0lGODlhGAAYAOfzAAAAAAIAAAMAAAYAAAUFBRIMCw4ODisLBBQUFCUSDiIXFR8fHygoKDg4
  OE9BFVpQLlxQK2FWL2JWN2FXOGVZMGZaMrs3GWxfNGFhYWdjWcBGK8FGKm9rY8NMMd9CHsRU
  O3R0cnV0cs9SNcdXPtxQMN9PLnx4b3p6d9xWOHx7echhSslkS4CAf4GAf4KBfuNdP4OCgN9f
  QYODgYSDgYaFgt9jRsxtWIiIhZCKgeVpTuJrUN9yWNB4ZZOTkJSUkd94X916Y5qVipuVit96
  YpuWipiXlJeXl5iXl52Xi5mYkeh5YJ2XjJmYl56Yjed7Y5uZl5+ZjZ+Zjpqal5qamZual5+a
  jqCajpubmaGbj6GbkJycnKGckOeBa6OdkaOdkp6enp+enKOekueDbaSek5+fnqGfnKGgnaGh
  oKGhodeQfaWjoKSko+qMd+KPfamppqqppquqp6urqqyrqKurq6yrqa2rqa2sqe2kPq+vrrCv
  rbCvrrGwrrOyr+eejbOysfCpP7Ozs7SzsbSzsrS0steudLW0srW0s7W1s7W1tLW1tba1tLe2
  tbi3tPOvQrm3tri4trm4uLm5ubq5t/SyRO+0Tbu7ufe1RPK2Tfe1Rb29vO6rm8C/vMDAwMPC
  vsXEwcnJx8rKyM3LyPbSNs3My83Nzc/OytDOyvjYN9DQz9LRzdHR0dPSzvncONTTz9PT0tPT
  09XTztbU0PnfOdfV0dfW0dbW1tjW0djW0tnX09nX1PrkOtrZ1dvZ1fvnO9za1tza2Nzb2Nzb
  2fzpO9zc2t3c2N3c2t7d2fzrPd/e2uDe2t/f3eDf2+Hf2+Hf3OHg3ODg3+Hg3eLh3ePi4OTj
  4OXj4OXk4eTk5Obl4ufm4+jn5Ofn5+np6evq6Ozr6e3s6u3t6+3t7e/v7vDw7vDw8PHw7vLy
  8vPy8fTz8vT09Pb19Pb29vj39vj49/n5+Pn5+fr6+fv7+/z8+/7+/v//////////////////
  /////////////////////////////////yH5BAEKAP8ALAAAAAAYABgAAAj+AP8JHJhAQIAB
  BwYqXKgQgEMdKEigEOGwogEGGBj+A/BKHQBNfdoAWQGglrt27bRZI7WAIQB18wCI+TFkx4gC
  tea1C4dn2zxADRYCmBeTS40YNToUQMMpU6I14+ahm0OgIVEATkpo3aDAFbx25b5UdGg1phIP
  aC0AIJMpU6QzjmTMIDtwqDwAZ9MCQLWunblnvz4B6HUJQN158RCwecH4AwAtlSAtUmQIwDFL
  EAwLHPoOAJscoFUgGHWutDkAwjBd0Lx5HjvPPADwsIFgyiNEgQDomjSBbut0ANIAiANAAwBQ
  5LwBkNVIAgAOrDfOOzcFAAsjTAC0ODIIACtKFQDYPDERfeg5c8o+DSNXTFIwAKf+UABwxQ6O
  8vPEIUJ0qJAgQX4AIModDwAAAgyeBIHfN9504yA32UgDACERACDFG520EgV+3Oyxhx555EEH
  AA44FIILPZixSxb4YXPNi9VQA4xDRVABRyer4IILFOW5Mw0dctRhhxtg3HBCCjT4UIYaatzS
  RHngQNOMM8tEY0wqjPCxSSix8IKLLbMgUZ4qzCSDjDHLEJNLKaZ0yYsvt9ACixDlJRHGGF50
  4cUWWFRhhRVZQAHFEksQkUF0G42l6KK+aeToowEBADs=
}

image create photo tb_play -data {
  R0lGODlhGAAYAKUjAAAAAGxranJxcHt7en18e39+fYKBgIaFg4mIhoyLiY+OjJCPjZmZlp2c
  mqGfnaGgnqWkoaemo6mopbCvrLSzsbWzsba0srm2tLm3tLq5try6t728ucPCv8XDwMfGw8fG
  xNDOzNLRztjX1f//////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////yH+FUNyZWF0ZWQg
  d2l0aCBUaGUgR0lNUAAh+QQBCgA/ACwAAAAAGAAYAAAGXsCfcEgsGo/IpHLJbDoBziQAGjUC
  BNTqEDAIZLWAAoPwjQIMjcmi3AQcHhQLhL0EICCYjIYDGJkTEhsdIH1VAAoVHiGFhg0XIoyG
  Dh+RhhGVhpiGflpEnJ2goaKjSEEAOw==
}

image create photo tb_pause -data {
  R0lGODlhGAAYAIQcAAAAAHNzcn5+fYSEg4WEg4iIh5GQjqSko6aloqalpKinpqqpp66tqa+u
  rLKwrbWzsLW0s7u6t7+9usC/vsPBvsrKyNHPzNTT0tfV09nY1t7d2/Pz8///////////////
  /yH+FUNyZWF0ZWQgd2l0aCBUaGUgR0lNUAAh+QQBCgAfACwAAAAAGAAYAAAFeOAnjmRpnmiq
  rmzrviYgy9xMs0AwFECt8xycQHHoAYbF4OqYgBgFzR6OsJgYqValCmBoVIzdrzbF9YLNY1RZ
  vJYuEZGLES5PnwD0edy9ZUgwRn6AdjEOFBlGhoiEJQAPFhpGj5GMJDZGNpUjHJycG52dMKKj
  pKUsIQA7
}
###
### End of file: analysis.tcl
###
###