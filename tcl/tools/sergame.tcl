###
### sergame.tcl: part of Scid.
### Copyright (C) 2007  Pascal Georges
###
################################################################################
# The number used for the engine playing a serious game is 3
################################################################################

namespace eval sergame {
  
  # DEBUG
  set ::uci::uciInfo(log_stdout3) 0
  
  # if true, follow a specific opening
  set isOpening 0
  set chosenOpening ""
  set openingMovesList {}
  set openingMovesHash {}
  set openingMoves ""
  set outOfOpening 0
  set useBook 1
  set bookToUse ""
  array set engineListBox {}
  set startFromCurrent 0
  set coachIsWatching 0
  set engineName ""
  set bookSlot 2
  set timeMode "timebonus"
  set depth 0
  set movetime 0
  set nodes 0
  set ponder 0
  # list of fen positions played to detect 3 fold repetition
  set lFen {}
  set lastPlayerMoveUci ""
  
  ################################################################################
  #
  ################################################################################
  proc config {} {
    global ::sergame::configWin ::sergame::chosenOpening
    
    # check if game window is already opened. If yes abort previous game
    set w ".serGameWin"
    if {[winfo exists $w]} {
      focus .
      destroy $w
    }
    
    set w ".configSerGameWin"
    if {[winfo exists $w]} {
      focus $w
      return
    }
    
    toplevel $w
    wm title $w "$::tr(configuregame)"
    
    bind $w <F1> { helpWindow SeriousGame }
    setWinLocation $w
    
    frame $w.fengines -relief groove -borderwidth 1
    frame $w.fbook -relief groove -borderwidth 1
    frame $w.ftime -relief groove -borderwidth 1
    frame $w.fopening -relief groove -borderwidth 1
    frame $w.fbuttons
    
    pack $w.fengines $w.fbook $w.ftime -side top -fill x
    pack $w.fopening -side top -fill both -expand 1
    pack $w.fbuttons -side top -fill x
    
    # builds the list of UCI engines
    frame $w.fengines.fEnginesList -relief raised -borderwidth 1
    listbox $w.fengines.fEnginesList.lbEngines -yscrollcommand "$w.fengines.fEnginesList.ybar set" \
        -height 5 -width 50 -exportselection 0
    scrollbar $w.fengines.fEnginesList.ybar -command "$w.fengines.fEnginesList.lbEngines yview"
    pack $w.fengines.fEnginesList.ybar -side left -fill y
    pack $w.fengines.fEnginesList.lbEngines -side left -fill both -expand yes
    pack $w.fengines.fEnginesList -expand yes -fill both -side top
    set i 0
    set idx 0
    foreach e $::engines(list) {
      if { [lindex $e 7] != 1} { incr idx ; continue }
      set ::sergame::engineListBox($i) $idx
      set name [lindex $e 0]
      $w.fengines.fEnginesList.lbEngines insert end $name
      incr i
      incr idx
    }
    $w.fengines.fEnginesList.lbEngines selection set 0
    
    # load book names
    checkbutton $w.fbook.cbUseBook -text $::tr(UseBook) -variable ::sergame::useBook
    set bookPath $::scidBooksDir
    ::combobox::combobox $w.fbook.combo -editable false -width 12
    set bookList [ lsort -dictionary [ glob -nocomplain -directory $bookPath *.bin ] ]
    set i 0
    set idx 0
    foreach file  $bookList {
      set f [ file tail $file ]
      $w.fbook.combo list insert end $f
    }
    $w.fbook.combo select 0
    pack $w.fbook.cbUseBook $w.fbook.combo -expand yes -fill both -side top
    
    set row 0
    
    radiobutton $w.ftime.rb1 -text $::tr(TimeBonus) -value "timebonus" -variable ::sergame::timeMode
    grid $w.ftime.rb1 -row $row -column 0 -sticky w
    incr row
    label $w.ftime.lb1 -text $::tr(WhiteTime)
    grid $w.ftime.lb1 -row $row -column 0 -sticky w
    incr row
    spinbox $w.ftime.spW1 -background white -width 4 -from 1 -to 120 -increment 1 -validate all -vcmd { regexp {^[0-9]+$} %P }
    spinbox $w.ftime.spW2 -background white -width 4 -from 0 -to 60 -increment 1 -validate all -vcmd { regexp {^[0-9]+$} %P }
    grid $w.ftime.spW1 -row $row -column 0 -sticky w
    grid $w.ftime.spW2  -row $row -column 1 -sticky w
    incr row
    
    label $w.ftime.lb2 -text $::tr(BlackTime)
    grid $w.ftime.lb2 -row $row -column 0 -sticky w
    incr row
    spinbox $w.ftime.spB1 -background white -width 4 -from 1 -to 120 -increment 1 -validate all -vcmd { regexp {^[0-9]+$} %P }
    spinbox $w.ftime.spB2 -background white -width 4 -from 0 -to 60 -increment 1 -validate all -vcmd { regexp {^[0-9]+$} %P }
    grid $w.ftime.spB1 -row $row -column 0 -sticky w
    grid $w.ftime.spB2  -row $row -column 1 -sticky w
    incr row
    
    $w.ftime.spW1 set 5
    $w.ftime.spB1 set 5
    $w.ftime.spW2 set 10
    $w.ftime.spB2 set 10
    
    radiobutton $w.ftime.rb2 -text $::tr(FixedDepth) -value "depth" -variable ::sergame::timeMode
    spinbox $w.ftime.sbDepth -background white -width 2 -from 1 -to 20 -increment 1 -validate all -vcmd { regexp {^[0-9]+$} %P }
    $w.ftime.sbDepth set 3
    
    radiobutton $w.ftime.rb3 -text "$::tr(Nodes) (x1000)" -value "nodes" -variable ::sergame::timeMode
    spinbox $w.ftime.sbNodes -background white -width 5 -from 5 -to 10000 -increment 5 -validate all -vcmd { regexp {^[0-9]+$} %P }
    $w.ftime.sbNodes set 10
    
    radiobutton $w.ftime.rb4 -text $::tr(SecondsPerMove) -value "movetime" -variable ::sergame::timeMode
    spinbox $w.ftime.sbMoveTime -background white -width 3 -from 1 -to 120 -increment 1 -validate all -vcmd { regexp {^[0-9]+$} %P }
    $w.ftime.sbMoveTime set 5
    
    grid $w.ftime.rb2 -row $row -column 0 -sticky w
    grid $w.ftime.sbDepth -row $row -column 1 -sticky w
    incr row
    grid $w.ftime.rb3 -row $row -column 0 -sticky w
    grid $w.ftime.sbNodes -row $row -column 1 -sticky w
    incr row
    grid $w.ftime.rb4 -row $row -column 0 -sticky w
    grid $w.ftime.sbMoveTime -row $row -column 1 -sticky w
    incr row
    
    # New game or use current position ?
    checkbutton $w.ftime.cbPosition -text $::tr(StartFromCurrentPosition) -variable ::sergame::startFromCurrent
    grid $w.ftime.cbPosition  -row $row -column 0 -sticky w
    incr row
    #
    #
    #If an engine is able to ponder it must tell it the GUI at startup (option name Ponder).
    # When pondering is swithed on the GUI sends:
    #
    # > setoption name Ponder value true
    #
    # After that the engine tells the pondermove with every move, but don?t start pondering itself.
    # Some engines send the pondermove also if pondering is switched off.
    # Most GUI?s accept the pondermove also if the engine don?t send the ponderoption at startup.
    #
    # < bestmove e2e4 ponder g8f6
    #
    # The GUI answers imediatelly with the ponder command:
    #
    # > position startpos moves h2h4 e7e5 d2d4 e5d4 d1d4 d7d5 e2e4 g8f6
    # > go ponder wtime 7188043 btime 7166483
    #
    # Some earlier versions of Fritz send this line also if an engine don?t support pondering. The pondermove is taken from the PV!
    #
    # Now the engine ponders, the GUI sends now:
    #
    # > ponderhit
    #
    # if the pondermove is played, or:
    #
    # > stop
    # > position startpos moves h2h4 e7e5 d2d4 e5d4 d1d4 d7d5 e2e4 h4h5
    #
    # if another move is played.
    #
    # In the UCI 2 protocol the engine is allowed to ponder on a different move than
    
    # ponder
    checkbutton $w.ftime.cbPonder -text $::tr(Ponder) -variable ::sergame::ponder
    grid $w.ftime.cbPonder  -row $row -column 0 -sticky w
    incr row
    
    # Warn if the user makes weak/bad moves
    checkbutton $w.ftime.cbCoach -text $::tr(CoachIsWatching) -variable ::sergame::coachIsWatching
    grid $w.ftime.cbCoach  -row $row -column 0 -sticky w
    incr row
    
    # choose a specific opening
    checkbutton $w.fopening.cbOpening -text $::tr(SpecificOpening) -variable ::sergame::isOpening
    frame $w.fopening.fOpeningList -relief raised -borderwidth 1
    listbox $w.fopening.fOpeningList.lbOpening -yscrollcommand "$w.fopening.fOpeningList.ybar set" \
        -height 5 -width 50 -list ::tacgame::openingList -exportselection 0
    $w.fopening.fOpeningList.lbOpening selection set 0
    scrollbar $w.fopening.fOpeningList.ybar -command "$w.fopening.fOpeningList.lbOpening yview"
    pack $w.fopening.fOpeningList.lbOpening -side right -fill both -expand 1
    pack $w.fopening.fOpeningList.ybar -side right -fill y
    pack $w.fopening.cbOpening -fill x -side top
    pack $w.fopening.fOpeningList -expand yes -fill both -side top -expand 1
    
    button $w.fbuttons.close -text $::tr(Play) -command {
      focus .
      set chosenEngine [.configSerGameWin.fengines.fEnginesList.lbEngines curselection]
      set ::sergame::engineName [.configSerGameWin.fengines.fEnginesList.lbEngines get $chosenEngine]
      set ::sergame::chosenOpening [.configSerGameWin.fopening.fOpeningList.lbOpening curselection]
      if {$::sergame::useBook} {
        set ::sergame::bookToUse [.configSerGameWin.fbook.combo get]
      }
      set ::uci::uciInfo(wtime3) [expr [.configSerGameWin.ftime.spW1 get]*1000*60]
      set ::uci::uciInfo(btime3) [expr [.configSerGameWin.ftime.spB1 get]*1000*60]
      set ::uci::uciInfo(winc3) [expr [.configSerGameWin.ftime.spW2 get]*1000]
      set ::uci::uciInfo(binc3) [expr [.configSerGameWin.ftime.spB2 get]*1000]
      set ::uci::uciInfo(fixeddepth3) [.configSerGameWin.ftime.sbDepth get]
      set ::uci::uciInfo(fixednodes3) [expr [.configSerGameWin.ftime.sbNodes get]*1000]
      set ::uci::uciInfo(movetime3) [expr [.configSerGameWin.ftime.sbMoveTime get]*1000]
      
      destroy .configSerGameWin
      ::sergame::play $chosenEngine
    }
    button $w.fbuttons.cancel -textvar ::tr(Cancel) -command "focus .; destroy $w"
    
    pack $w.fbuttons.close $w.fbuttons.cancel -expand yes -side left -padx 20 -pady 2
    
    bind $w <Escape> { .configSerGameWin.fbuttons.cancel invoke }
    bind $w <Return> { .configSerGameWin.fbuttons.close invoke }
    bind $w <F1> { helpWindow SeriousGame }
    bind $w <Destroy> ""
    bind $w <Configure> "recordWinSize $w"
    wm minsize $w 45 0
  }
  
  ################################################################################
  #
  ################################################################################
  proc play { engine {n 3} } {
    global ::sergame::chosenOpening ::sergame::isOpening ::tacgame::openingList ::sergame::openingMovesList \
        ::sergame::openingMovesHash ::sergame::openingMoves ::sergame::outOfOpening
    
    set ::sergame::lFen {}
    
    ::uci::startEngine $::sergame::engineListBox($engine) $n
    set ::uci::uciInfo(prevscore$n) 0.0
    set ::uci::uciInfo(ponder$n) ""
    
    if {$::sergame::startFromCurrent} {
      set isOpening 0
    }
    
    # ponder
    if {$::sergame::ponder} {
      ::sergame::sendToEngine $n "setoption name Ponder value true"
    } else {
      ::sergame::sendToEngine $n "setoption name Ponder value false"
    }
    
    # if will follow a specific opening line
    if {$isOpening} {
      set fields [split [lindex $openingList $chosenOpening] ":"]
      set openingName [lindex $fields 0]
      set openingMoves [string trim [lindex $fields 1]]
      set openingMovesList ""
      set openingMovesHash ""
      set outOfOpening 0
      foreach m [split $openingMoves] {
        # in case of multiple adjacent spaces in opening line
        if {$m =={}} {
          continue
        }
        set p [string trim $m]
        lappend openingMovesList [string trim [regsub {^[1-9]+\.} $p ""] ]
      }
      
      sc_game new
      lappend openingMovesHash [sc_pos hash]
      foreach m  $openingMovesList {
        if {[catch {sc_move addSan $m}]} { }
        lappend openingMovesHash [sc_pos hash]
      }
    }
    if {!$::sergame::startFromCurrent} {
      # create a new game if a DB is opened
      sc_game new
      sc_game tags set -event "Serious game"
      if { [::board::isFlipped .board] } {
        sc_game tags set -white "$::sergame::engineName"
      } else  {
        sc_game tags set -black "$::sergame::engineName"
      }
      sc_game tags set -date [::utils::date::today]
      if {[sc_base inUse [sc_base current]]} { catch {sc_game save 0}  }
    }
    
    updateBoard -pgn
    ::windows::gamelist::Refresh
    updateTitle
    updateMenuStates
    set w ".serGameWin"
    if {[winfo exists $w]} {
      focus .
      destroy $w
      return
    }
    
    toplevel $w
    wm title $w "$::tr(coachgame) ($::sergame::engineName)"
    
    setWinLocation $w
    
    frame $w.fclocks -relief raised -borderwidth 1
    frame $w.fbuttons
    pack $w.fclocks $w.fbuttons -side top -expand yes -fill both
    
    ::gameclock::new $w.fclocks 2 80 1
    ::gameclock::new $w.fclocks 1 80 1
    ::gameclock::reset 1
    ::gameclock::start 1
    
    button $w.fbuttons.close -textvar ::tr(Abort) -command ::sergame::abortGame
    pack $w.fbuttons.close -expand yes -fill both -padx 20 -pady 2
    
    bind $w <F1> { helpWindow TacticalGame }
    bind $w <Destroy> ::sergame::abortGame
    bind $w <Escape> ::sergame::abortGame
    bind $w <Configure> "recordWinSize $w"
    wm minsize $w 45 0
    
    # setup clocks
    if { [::sergame::getEngineColor] == "white" } {
      ::gameclock::setSec 2 [expr 0 - $::uci::uciInfo(wtime$n)/1000]
      ::gameclock::setSec 1 [expr 0 - $::uci::uciInfo(btime$n)/1000]
    } else  {
      ::gameclock::setSec 1 [expr 0 - $::uci::uciInfo(wtime$n)/1000]
      ::gameclock::setSec 2 [expr 0 - $::uci::uciInfo(btime$n)/1000]
    }
    
    set ::sergame::wentOutOfBook 0
    ::sergame::engineGo $n
  }
  ################################################################################
  #
  ################################################################################
  proc abortGame { { n 3 } } {
    set ::sergame::lFen {}
    if { $::uci::uciInfo(pipe$n) == ""} { return }
    after cancel ::sergame::engineGo $n
    ::uci::closeUCIengine $n
    ::gameclock::stop 1
    ::gameclock::stop 2
    set ::uci::uciInfo(bestmove$n) "abort"
    destroy .serGameWin
    focus .
  }
  
  ################################################################################
  #
  ################################################################################
  proc sendToEngine {n text} {
    ::sergame::logEngine $n "Scid  : $text"
    catch {puts $::uci::uciInfo(pipe$n) $text}
  }
  ################################################################################
  # returns true if last move is a mate and stops clocks
  ################################################################################
  proc endOfGame {} {
    set move_done [sc_game info previousMove]
    if { [string index [sc_game info previousMove] end ] == "#"} {
      ::gameclock::stop 1
      ::gameclock::stop 2
      return 1
    }
    return 0
  }
  ################################################################################
  #
  ################################################################################
  proc engineGo { n } {
    global ::sergame::isOpening ::sergame::openingMovesList ::sergame::openingMovesHash ::sergame::openingMoves \
        ::sergame::timeMode ::sergame::outOfOpening
    
    after cancel ::sergame::engineGo $n
    
    if { [::sergame::endOfGame] } { return }
    
    if { [sc_pos side] != [::sergame::getEngineColor] } {
      after 1000 ::sergame::engineGo $n
      return
    }
    
    # The player moved : add clock time
    if {!([::sergame::getEngineColor] == "black" && [sc_pos moveNumber] == 1)} {
      if { [::sergame::getEngineColor] == "white" } {
        ::gameclock::add 1 [expr $::uci::uciInfo(binc$n)/1000]
      } else  {
        ::gameclock::add 1 [expr $::uci::uciInfo(winc$n)/1000]
      }
    }
    ::gameclock::stop 1
    ::gameclock::start 2
    repetition
    
    # make a move corresponding to a specific opening, (it is engine's turn)
    if {$isOpening && !$outOfOpening} {
      set index 0
      # Warn if the user went out of the opening line chosen
      if { !$outOfOpening } {
        set ply [ expr [sc_pos moveNumber] * 2 - 1]
        if { [sc_pos side] == "white" } {
          set ply [expr $ply - 1]
        }
        
        if { [lsearch $openingMovesHash [sc_pos hash]] == -1 && [llength $openingMovesList] >= $ply} {
          set answer [tk_messageBox -icon question -parent .board -title $::tr(OutOfOpening) -type yesno \
              -message "$::tr(NotFollowedLine) $openingMoves\n $::tr(DoYouWantContinue)" ]
          if {$answer == no} {
            sc_move back 1
            updateBoard -pgn
            ::gameclock::stop 2
            ::gameclock::start 1
            after 1000 ::sergame::engineGo $n
            return
          }  else  {
            set outOfOpening 1
          }
        }
      }
      
      set hpos [sc_pos hash]
      # Find a corresponding position in the opening line
      set length [llength $openingMovesHash]
      for {set i 0}   { $i < [expr $length-1] } { incr i } {
        set h [lindex $openingMovesHash $i]
        if {$h == $hpos} {
          set index [lsearch $openingMovesHash $h]
          set move [lindex $openingMovesList $index]
          # play the move
          set action "replace"
          if {![sc_pos isAt vend]} { set action [confirmReplaceMove] }
          if {$action == "replace"} {
            if {[catch {sc_move addSan $move}]} {}
          } elseif {$action == "var"} {
            sc_var create
            if {[catch {sc_move addSan $move}]} {}
          } elseif {$action == "mainline"} {
            sc_var create
            if {[catch {sc_move addSan $move}]} {}
            sc_var exit
            sc_var promote [expr {[sc_var count] - 1}]
            sc_move forward 1
          }
          
          updateBoard -pgn -animate
          ::gameclock::stop 2
          ::gameclock::start 1
          repetition
          if { [::sergame::getEngineColor] == "white" } {
            ::gameclock::add 2 [expr $::uci::uciInfo(winc$n)/1000]
          } else  {
            ::gameclock::add 2 [expr $::uci::uciInfo(binc$n)/1000]
          }
          after 1000 ::sergame::engineGo $n
          return
        }
      }
    }
    # -------------------------------------------------------------
    # use a book
    if {$::sergame::useBook && ! $::sergame::wentOutOfBook} {
      set move [ ::book::getMove $::sergame::bookToUse [sc_pos fen] $::sergame::bookSlot]
      if {$move == ""} {
        set ::sergame::wentOutOfBook 1
      } else  {
        sc_move addSan $move
        ::utils::sound::AnnounceNewMove $move
        # we made a book move so assume a score = 0
        set ::uci::uciInfo(prevscore$n) 0.0
        updateBoard -pgn -animate
        ::gameclock::stop 2
        ::gameclock::start 1
        repetition
        if {$timeMode == "timebonus"} {
          if { [::sergame::getEngineColor] == "white" } {
            ::gameclock::add 2 [expr $::uci::uciInfo(winc$n)/1000]
          } else  {
            ::gameclock::add 2 [expr $::uci::uciInfo(binc$n)/1000]
          }
        }
        after 1000 ::sergame::engineGo $n
        return
      }
    }
    # -------------------------------------------------------------
    # check if the engine pondered on the right move
    
    if { $::sergame::ponder && $::uci::uciInfo(ponder$n) == $::sergame::lastPlayerMoveUci} {
      ::sergame::sendToEngine $n "ponderhit"
    } else {
      
      if { $::sergame::ponder } {
        ::sergame::sendToEngine $n "stop"
      }
      set ::analysis(waitForReadyOk$n) 1
      ::sergame::sendToEngine $n "isready"
      vwait ::analysis(waitForReadyOk$n)
      ::sergame::sendToEngine $n "position fen [sc_pos fen]"
      if { [::sergame::getEngineColor] == "white" } {
        set wtime [expr [::gameclock::getSec 2] * 1000 ]
        set btime [expr [::gameclock::getSec 1] * 1000 ]
      } else  {
        set wtime [expr [::gameclock::getSec 1] * 1000 ]
        set btime [expr [::gameclock::getSec 2] * 1000 ]
      }
      if {$timeMode == "timebonus"} {
        ::sergame::sendToEngine $n "go wtime $wtime btime $btime winc $::uci::uciInfo(winc$n) binc $::uci::uciInfo(binc$n)"
      } elseif {$timeMode == "depth"} {
        ::sergame::sendToEngine $n "go depth $::uci::uciInfo(fixeddepth$n)"
      } elseif {$timeMode == "movetime"} {
        ::sergame::sendToEngine $n "go movetime $::uci::uciInfo(movetime$n)"
      } elseif {$timeMode == "nodes"} {
        ::sergame::sendToEngine $n "go nodes $::uci::uciInfo(fixednodes$n)"
      }
    }
    
    set ::uci::uciInfo(bestmove$n) ""
    vwait ::uci::uciInfo(bestmove$n)

    # -------------------------------------------------------------
    # if weak move detected, propose the user to tack back
    if { $::sergame::coachIsWatching && $::uci::uciInfo(prevscore$n) != "" } {
      set blunder 0
      set delta [expr $::uci::uciInfo(score$n) - $::uci::uciInfo(prevscore$n)]
      if {$delta > $::informant("?!") && [getEngineColor] == "white" ||
        $delta < [expr 0.0 - $::informant("?!")] && [getEngineColor] == "black" } {
        set blunder 1
      }
      
      if {$delta > $::informant("?") && [getEngineColor] == "white" ||
        $delta < [expr 0.0 - $::informant("?")] && [getEngineColor] == "black" } {
        set blunder 2
      }
      
      if {$delta > $::informant("??") && [getEngineColor] == "white" ||
        $delta < [expr 0.0 - $::informant("??")] && [getEngineColor] == "black" } {
        set blunder 3
      }
      
      if {$blunder == 1} {
        set tBlunder "DubiousMovePlayedTakeBack"
      } elseif {$blunder == 2} {
        set tBlunder "WeakMovePlayedTakeBack"
      } elseif {$blunder == 3} {
        set tBlunder "BadMovePlayedTakeBack"
      }
      
      if {$blunder != 0} {
        set answer [tk_messageBox -icon question -parent .board -title "Scid" -type yesno -message $::tr($tBlunder) ]
        if {$answer == yes} {
          sc_move back 1
          updateBoard -pgn
          ::gameclock::stop 2
          ::gameclock::start 1
          after 1000 ::sergame::engineGo $n
          return
        }
      }
    }
    
    # ------------------------------------------------------------- 
    if { $::uci::uciInfo(bestmove$n) == "abort" } {
      return
    }
    
    ::uci::sc_move_add $::uci::uciInfo(bestmove$n)
    ::utils::sound::AnnounceNewMove $::uci::uciInfo(bestmove$n)
    set ::uci::uciInfo(prevscore$n) $::uci::uciInfo(score$n)
    updateBoard -pgn -animate
    repetition
    
    # add time after a move played
    if {$timeMode == "timebonus"} {
      if { [::sergame::getEngineColor] == "white" } {
        ::gameclock::add 2 [expr $::uci::uciInfo(winc$n)/1000]
      } else  {
        ::gameclock::add 2 [expr $::uci::uciInfo(binc$n)/1000]
      }
    }
    ::gameclock::stop 2
    ::gameclock::start 1
    
    # ponder mode (the engine just played its move)
    if {$::sergame::ponder && $::uci::uciInfo(ponder$n) != ""} {
      ::sergame::sendToEngine $n "position fen [sc_pos fen] moves $::uci::uciInfo(ponder$n)"
      if { [::sergame::getEngineColor] == "white" } {
        set wtime [expr [::gameclock::getSec 2] * 1000 ]
        set btime [expr [::gameclock::getSec 1] * 1000 ]
      } else  {
        set wtime [expr [::gameclock::getSec 1] * 1000 ]
        set btime [expr [::gameclock::getSec 2] * 1000 ]
      }
      if {$timeMode == "timebonus"} {
        ::sergame::sendToEngine $n "go ponder wtime $wtime btime $btime winc $::uci::uciInfo(winc$n) binc $::uci::uciInfo(binc$n)"
      } elseif {$timeMode == "depth"} {
        ::sergame::sendToEngine $n "go ponder depth $::uci::uciInfo(fixeddepth$n)"
      } elseif {$timeMode == "movetime"} {
        ::sergame::sendToEngine $n "go ponder movetime $::uci::uciInfo(movetime$n)"
      } elseif {$timeMode == "nodes"} {
        ::sergame::sendToEngine $n "go ponder nodes $::uci::uciInfo(fixednodes$n)"
      }
    }
    
    after 1000 ::sergame::engineGo $n
  }
  ################################################################################
  #   add current position for 3fold repetition detection and returns 1 if
  # the position is a repetion
  ################################################################################
  proc repetition {} {
    set elt [lrange [split [sc_pos fen]] 0 2]
    lappend ::sergame::lFen $elt
    if { [llength [lsearch -all $::sergame::lFen $elt] ] >=3 } {
      tk_messageBox -type ok -message $::tr(Draw) -parent .board -icon info
      puts $::sergame::lFen
      return 1
    }
    return 0
  }
  ################################################################################
  #
  ################################################################################
  proc getEngineColor {} {
    # Engine always plays for the upper side
    if { [::board::isFlipped .board] == 0 } {
      return "black"
    } else  {
      return "white"
    }
  }
  
  ################################################################################
  #
  ################################################################################
  proc logEngine {n text} {
    if {$::uci::uciInfo(log_stdout$n)} {
      puts stdout "$n $text"
    }
  }
  
}
###
### End of file: sergame.tcl
###