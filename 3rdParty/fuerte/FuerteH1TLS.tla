------------------------------ MODULE FuerteH1TLS ---------------------------
EXTENDS Integers, TLC, Sequences

(*
--algorithm H1Connection {

variables   \* VERIFIED
  state = "Disconnected",       \* this is a member variable in the program
  active = FALSE,     \* this is a member variable in the program
  queueSize = 0,      \* this is the length of the input queue
  alarm = "off",      \* this encodes, if an alarm is set
  asyncRunning = "none",   \* this encodes, if an async operation is scheduled
  iocontext = << >>,  \* this is what is posted on the iocontext
                      \* the following are all member variables in the object
  reading = FALSE,    \* set from the moment the asyncRead is posted until
                      \* the completion handler has executed
  writing = FALSE,    \* set from the moment the asyncWrite is posted until
                      \* the completion handler has executed
                      \* both are read in the corresponding timeout
                      \* to decide if the completion handler has already
                      \* finished

procedure startConnection() {   \* VERIFIED
(* This is called whenever the connection broke and we want to immediately
   reconnect. Therefore we know that the state is "Disconnected" and we
   are active and no alarm is set. *)
 startConnectionBegin:
  assert /\ state = "Disconnected"
         /\ active
         /\ asyncRunning = "none"
         /\ alarm = "off";
  state := "Connecting";
  alarm := "connectAlarm";
  asyncRunning := "connect";
  return;
};

procedure terminateActivity() {    \* VERIFIED
(* This is called when a connection goes to Failed state and we want to
   immediately shut down all activity. We must do this in a way that
   avoids a sleeping barber in case new requests are posted concurrently. *)
 terminateActivityBegin:
  assert /\ state = "Failed"
         /\ asyncRunning = "none"
         /\ alarm = "off";
 terminateLoop: 
  while (TRUE) {
    drain:
      queueSize := 0;
    deactivate2:
      active := FALSE;
    checkAgain2:
      if (queueSize = 0) {
        return;
      };
    reactivate2:
      active := TRUE;
  };
};

procedure asyncWriteNextRequest() {     \* VERIFIED
(* This is called whenever we are active and potentially want to continue
   writing. It can also be called if we are in the "Failed" state. In this
   case the purpose is to reset the `active` flag, which is exclusively
   done in this procedure. *)
 asyncWriteNextRequestBegin:
  assert /\ state \in {"Connected", "Failed"}
         /\ active
         /\ asyncRunning = "none";
  (* We use the check-set-check pattern to make sure we are not going to
     sleep although somebody has posted something on the queue. *)
  check: { 
    if (queueSize = 0) {
      deactivate:
        \* This is the only place which is allowed to set active to FALSE:
        active := FALSE;
      checkAgain: {
        if (queueSize = 0) {
          if (state = "Connected") {
            alarm := "idleAlarm";
          };
          return;
        };
        reactivate:
          if (active) {
            \* if somebody else has set active instead of us (after we
            \* have set it to false above), he is also responsible for
            \* starting the write.
            return;
          } else {
            active := TRUE;
          }
      }
    };
  };
  pop: {
    queueSize := queueSize - 1;
    alarm := "writeAlarm";
    asyncRunning := "write";
    writing := TRUE;
    return;
  }
};

  
process(fuerte = "fuertethread") {
  loop:
    while (TRUE) {
      either activate:   \* VERIFIED
        if (Len(iocontext) >= 1 /\ Head(iocontext) = "activate") {
          assert state /= "Connecting";
          iocontext := Tail(iocontext);
          if (active) {
            if (state = "Disconnected") {
              call startConnection();
            } else if (state = "Connected") {
              call asyncWriteNextRequest();
            } else if (state = "Failed") {
              call terminateActivity();
            };
          };
        };
      
      or connectDone:    \* VERIFIED
        if (/\ Len(iocontext) >= 1
            /\ Head(iocontext) \in {"connect", "connectBAD"}) {
          assert active /\ state \in {"Connecting", "Disconnected", "Failed"};
          alarm := "off";
          if (Head(iocontext) = "connect" /\ state = "Connecting") {
            iocontext := Tail(iocontext);
            state := "Connected";
            call asyncWriteNextRequest();
          } else {
            (* for the sake of simplicity we ignore the retries here and
               directly go to the Failed state *)
            iocontext := Tail(iocontext);
            state := "Failed";
            call terminateActivity();
          }; 
        };
      
      or writeDone:   \* VERIFIED
        if (/\ Len(iocontext) >= 1
            /\ Head(iocontext) \in {"write", "writeBAD"}) {
          assert /\ active
                 /\ state \in {"Connected", "Disconnected", "Failed"}
                 /\ writing;
          writing := FALSE;
          if (Head(iocontext) = "write" /\ state = "Connected") {
            iocontext := Tail(iocontext);
            asyncRunning := "read";
            reading := TRUE;
            alarm := "readAlarm";
          } else {
            iocontext := Tail(iocontext);
            alarm := "off";
            state := "Failed";
            call terminateActivity();
          };
        };
      
      or readDone:   \* VERIFIED
        if (/\ Len(iocontext) >= 1
            /\ Head(iocontext) \in {"read", "readBAD"}) {
          assert active /\ state \in {"Connected", "Disconnected", "Failed"}; 
          alarm := "off";
          reading := FALSE;
          if (Head(iocontext) = "read" /\ state = "Connected") {
            iocontext := Tail(iocontext);
            call asyncWriteNextRequest();
          } else {
            iocontext := Tail(iocontext);
            state := "Failed";
            call terminateActivity();
          };
        };
      
      or cancellation:   \* VERIFIED
        if (/\ Len(iocontext) >= 1 /\ Head(iocontext) = "cancel") {
          iocontext := Tail(iocontext);
          \* Note that we *do not* set active to FALSE here, since we want
          \* to interfere as little as possible with the active business.
          state := "Failed";
          queueSize := 0;
          alarm := "off";
          if (asyncRunning = "connect") {
            asyncRunning := "connectBAD";
          } else if (asyncRunning = "write") {
            asyncRunning := "writeBAD";
          } else if (asyncRunning = "read") {
            asyncRunning := "readBAD";
          };
        };

      or alarmTriggered:   \* VERIFIED
        if (alarm /= "off") {
          iocontext := Append(iocontext, alarm);
          alarm := "off";
        };
      
      or asyncFinished:    \* VERIFIED
        if (asyncRunning /= "none") {
          iocontext := Append(iocontext, asyncRunning);
          asyncRunning := "none";
        };

      or handleConnectAlarm:   \* VERIFIED
        if (Len(iocontext) >= 1 /\ Head(iocontext) = "connectAlarm") {
          iocontext := Tail(iocontext);
          if (asyncRunning = "connect") {
            asyncRunning := "connectBAD";    \* indicate error on socket
          }
        };
      
      or handleWriteAlarm:    \* VERIFIED
        if (Len(iocontext) >= 1 /\ Head(iocontext) = "writeAlarm") {
          iocontext := Tail(iocontext);
          if (writing /\ asyncRunning = "write") {
            \* note that we might have been scheduled by an off-going
            \* alarm but the writeDone which wants to disarm the alarm
            \* was scheduled already earlier, in this case we must not
            \* interfere
            asyncRunning := "writeBAD";
          }
        };
      
      or handleReadAlarm:    \* VERIFIED
        if (Len(iocontext) >= 1 /\ Head(iocontext) = "readAlarm") {
          iocontext := Tail(iocontext);
          if (reading /\ asyncRunning = "read") {
            \* note that we might have been scheduled by an off-going
            \* alarm but the readDone which wants to disarm the alarm
            \* was scheduled already earlier, in this case we must not
            \* interfere
            asyncRunning := "readBAD";
          }
        };
      
      or handleIdleAlarm:  \* VERIFIED
        if (Len(iocontext) >= 1 /\ Head(iocontext) = "idleAlarm") {
          iocontext := Tail(iocontext);
          if (~ active /\ state = "Connected") {
            state := "Failed";
            alarm := "off";
            call terminateActivity();
            \* it is possible that the idle alarm was still set, since we have
            \* gone to sleep and we have been posted on the iocontext beforehand
          }
        };
        
      or skip;
    }
};

process(client = "clientthread") {
  sendMessage:   \* VERIFIED
    while (TRUE) {
        await queueSize < 2 /\ state /= "Failed";
      pushQueue:
        queueSize := queueSize + 1;
      postActivate:
        if (~ active) {
          active := TRUE;
          iocontext := Append(iocontext, "activate");
        };
    };
};

process(cancel = "cancelthread") {
  cancelBegin:    \* VERIFIED
    iocontext := Append(iocontext, "cancel");
};

}
*)
\* BEGIN TRANSLATION
VARIABLES state, active, queueSize, alarm, asyncRunning, iocontext, reading, 
          writing, pc, stack

vars == << state, active, queueSize, alarm, asyncRunning, iocontext, reading, 
           writing, pc, stack >>

ProcSet == {"fuertethread"} \cup {"clientthread"} \cup {"cancelthread"}

Init == (* Global variables *)
        /\ state = "Disconnected"
        /\ active = FALSE
        /\ queueSize = 0
        /\ alarm = "off"
        /\ asyncRunning = "none"
        /\ iocontext = << >>
        /\ reading = FALSE
        /\ writing = FALSE
        /\ stack = [self \in ProcSet |-> << >>]
        /\ pc = [self \in ProcSet |-> CASE self = "fuertethread" -> "loop"
                                        [] self = "clientthread" -> "sendMessage"
                                        [] self = "cancelthread" -> "cancelBegin"]

startConnectionBegin(self) == /\ pc[self] = "startConnectionBegin"
                              /\ Assert(/\ state = "Disconnected"
                                        /\ active
                                        /\ asyncRunning = "none"
                                        /\ alarm = "off", 
                                        "Failure of assertion at line 28, column 3.")
                              /\ state' = "Connecting"
                              /\ alarm' = "connectAlarm"
                              /\ asyncRunning' = "connect"
                              /\ pc' = [pc EXCEPT ![self] = Head(stack[self]).pc]
                              /\ stack' = [stack EXCEPT ![self] = Tail(stack[self])]
                              /\ UNCHANGED << active, queueSize, iocontext, 
                                              reading, writing >>

startConnection(self) == startConnectionBegin(self)

terminateActivityBegin(self) == /\ pc[self] = "terminateActivityBegin"
                                /\ Assert(/\ state = "Failed"
                                          /\ asyncRunning = "none"
                                          /\ alarm = "off", 
                                          "Failure of assertion at line 43, column 3.")
                                /\ pc' = [pc EXCEPT ![self] = "terminateLoop"]
                                /\ UNCHANGED << state, active, queueSize, 
                                                alarm, asyncRunning, iocontext, 
                                                reading, writing, stack >>

terminateLoop(self) == /\ pc[self] = "terminateLoop"
                       /\ pc' = [pc EXCEPT ![self] = "drain"]
                       /\ UNCHANGED << state, active, queueSize, alarm, 
                                       asyncRunning, iocontext, reading, 
                                       writing, stack >>

drain(self) == /\ pc[self] = "drain"
               /\ queueSize' = 0
               /\ pc' = [pc EXCEPT ![self] = "deactivate2"]
               /\ UNCHANGED << state, active, alarm, asyncRunning, iocontext, 
                               reading, writing, stack >>

deactivate2(self) == /\ pc[self] = "deactivate2"
                     /\ active' = FALSE
                     /\ pc' = [pc EXCEPT ![self] = "checkAgain2"]
                     /\ UNCHANGED << state, queueSize, alarm, asyncRunning, 
                                     iocontext, reading, writing, stack >>

checkAgain2(self) == /\ pc[self] = "checkAgain2"
                     /\ IF queueSize = 0
                           THEN /\ pc' = [pc EXCEPT ![self] = Head(stack[self]).pc]
                                /\ stack' = [stack EXCEPT ![self] = Tail(stack[self])]
                           ELSE /\ pc' = [pc EXCEPT ![self] = "reactivate2"]
                                /\ stack' = stack
                     /\ UNCHANGED << state, active, queueSize, alarm, 
                                     asyncRunning, iocontext, reading, writing >>

reactivate2(self) == /\ pc[self] = "reactivate2"
                     /\ active' = TRUE
                     /\ pc' = [pc EXCEPT ![self] = "terminateLoop"]
                     /\ UNCHANGED << state, queueSize, alarm, asyncRunning, 
                                     iocontext, reading, writing, stack >>

terminateActivity(self) == terminateActivityBegin(self)
                              \/ terminateLoop(self) \/ drain(self)
                              \/ deactivate2(self) \/ checkAgain2(self)
                              \/ reactivate2(self)

asyncWriteNextRequestBegin(self) == /\ pc[self] = "asyncWriteNextRequestBegin"
                                    /\ Assert(/\ state \in {"Connected", "Failed"}
                                              /\ active
                                              /\ asyncRunning = "none", 
                                              "Failure of assertion at line 67, column 3.")
                                    /\ pc' = [pc EXCEPT ![self] = "check"]
                                    /\ UNCHANGED << state, active, queueSize, 
                                                    alarm, asyncRunning, 
                                                    iocontext, reading, 
                                                    writing, stack >>

check(self) == /\ pc[self] = "check"
               /\ IF queueSize = 0
                     THEN /\ pc' = [pc EXCEPT ![self] = "deactivate"]
                     ELSE /\ pc' = [pc EXCEPT ![self] = "pop"]
               /\ UNCHANGED << state, active, queueSize, alarm, asyncRunning, 
                               iocontext, reading, writing, stack >>

deactivate(self) == /\ pc[self] = "deactivate"
                    /\ active' = FALSE
                    /\ pc' = [pc EXCEPT ![self] = "checkAgain"]
                    /\ UNCHANGED << state, queueSize, alarm, asyncRunning, 
                                    iocontext, reading, writing, stack >>

checkAgain(self) == /\ pc[self] = "checkAgain"
                    /\ IF queueSize = 0
                          THEN /\ IF state = "Connected"
                                     THEN /\ alarm' = "idleAlarm"
                                     ELSE /\ TRUE
                                          /\ alarm' = alarm
                               /\ pc' = [pc EXCEPT ![self] = Head(stack[self]).pc]
                               /\ stack' = [stack EXCEPT ![self] = Tail(stack[self])]
                          ELSE /\ pc' = [pc EXCEPT ![self] = "reactivate"]
                               /\ UNCHANGED << alarm, stack >>
                    /\ UNCHANGED << state, active, queueSize, asyncRunning, 
                                    iocontext, reading, writing >>

reactivate(self) == /\ pc[self] = "reactivate"
                    /\ IF active
                          THEN /\ pc' = [pc EXCEPT ![self] = Head(stack[self]).pc]
                               /\ stack' = [stack EXCEPT ![self] = Tail(stack[self])]
                               /\ UNCHANGED active
                          ELSE /\ active' = TRUE
                               /\ pc' = [pc EXCEPT ![self] = "pop"]
                               /\ stack' = stack
                    /\ UNCHANGED << state, queueSize, alarm, asyncRunning, 
                                    iocontext, reading, writing >>

pop(self) == /\ pc[self] = "pop"
             /\ queueSize' = queueSize - 1
             /\ alarm' = "writeAlarm"
             /\ asyncRunning' = "write"
             /\ writing' = TRUE
             /\ pc' = [pc EXCEPT ![self] = Head(stack[self]).pc]
             /\ stack' = [stack EXCEPT ![self] = Tail(stack[self])]
             /\ UNCHANGED << state, active, iocontext, reading >>

asyncWriteNextRequest(self) == asyncWriteNextRequestBegin(self)
                                  \/ check(self) \/ deactivate(self)
                                  \/ checkAgain(self) \/ reactivate(self)
                                  \/ pop(self)

loop == /\ pc["fuertethread"] = "loop"
        /\ \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "activate"]
           \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "connectDone"]
           \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "writeDone"]
           \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "readDone"]
           \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "cancellation"]
           \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "alarmTriggered"]
           \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "asyncFinished"]
           \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "handleConnectAlarm"]
           \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "handleWriteAlarm"]
           \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "handleReadAlarm"]
           \/ /\ pc' = [pc EXCEPT !["fuertethread"] = "handleIdleAlarm"]
           \/ /\ TRUE
              /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
        /\ UNCHANGED << state, active, queueSize, alarm, asyncRunning, 
                        iocontext, reading, writing, stack >>

activate == /\ pc["fuertethread"] = "activate"
            /\ IF Len(iocontext) >= 1 /\ Head(iocontext) = "activate"
                  THEN /\ Assert(state /= "Connecting", 
                                 "Failure of assertion at line 111, column 11.")
                       /\ iocontext' = Tail(iocontext)
                       /\ IF active
                             THEN /\ IF state = "Disconnected"
                                        THEN /\ stack' = [stack EXCEPT !["fuertethread"] = << [ procedure |->  "startConnection",
                                                                                                pc        |->  "loop" ] >>
                                                                                            \o stack["fuertethread"]]
                                             /\ pc' = [pc EXCEPT !["fuertethread"] = "startConnectionBegin"]
                                        ELSE /\ IF state = "Connected"
                                                   THEN /\ stack' = [stack EXCEPT !["fuertethread"] = << [ procedure |->  "asyncWriteNextRequest",
                                                                                                           pc        |->  "loop" ] >>
                                                                                                       \o stack["fuertethread"]]
                                                        /\ pc' = [pc EXCEPT !["fuertethread"] = "asyncWriteNextRequestBegin"]
                                                   ELSE /\ IF state = "Failed"
                                                              THEN /\ stack' = [stack EXCEPT !["fuertethread"] = << [ procedure |->  "terminateActivity",
                                                                                                                      pc        |->  "loop" ] >>
                                                                                                                  \o stack["fuertethread"]]
                                                                   /\ pc' = [pc EXCEPT !["fuertethread"] = "terminateActivityBegin"]
                                                              ELSE /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                                                                   /\ stack' = stack
                             ELSE /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                                  /\ stack' = stack
                  ELSE /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                       /\ UNCHANGED << iocontext, stack >>
            /\ UNCHANGED << state, active, queueSize, alarm, asyncRunning, 
                            reading, writing >>

connectDone == /\ pc["fuertethread"] = "connectDone"
               /\ IF /\ Len(iocontext) >= 1
                     /\ Head(iocontext) \in {"connect", "connectBAD"}
                     THEN /\ Assert(active /\ state \in {"Connecting", "Disconnected", "Failed"}, 
                                    "Failure of assertion at line 127, column 11.")
                          /\ alarm' = "off"
                          /\ IF Head(iocontext) = "connect" /\ state = "Connecting"
                                THEN /\ iocontext' = Tail(iocontext)
                                     /\ state' = "Connected"
                                     /\ stack' = [stack EXCEPT !["fuertethread"] = << [ procedure |->  "asyncWriteNextRequest",
                                                                                        pc        |->  "loop" ] >>
                                                                                    \o stack["fuertethread"]]
                                     /\ pc' = [pc EXCEPT !["fuertethread"] = "asyncWriteNextRequestBegin"]
                                ELSE /\ iocontext' = Tail(iocontext)
                                     /\ state' = "Failed"
                                     /\ stack' = [stack EXCEPT !["fuertethread"] = << [ procedure |->  "terminateActivity",
                                                                                        pc        |->  "loop" ] >>
                                                                                    \o stack["fuertethread"]]
                                     /\ pc' = [pc EXCEPT !["fuertethread"] = "terminateActivityBegin"]
                     ELSE /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                          /\ UNCHANGED << state, alarm, iocontext, stack >>
               /\ UNCHANGED << active, queueSize, asyncRunning, reading, 
                               writing >>

writeDone == /\ pc["fuertethread"] = "writeDone"
             /\ IF /\ Len(iocontext) >= 1
                   /\ Head(iocontext) \in {"write", "writeBAD"}
                   THEN /\ Assert(/\ active
                                  /\ state \in {"Connected", "Disconnected", "Failed"}
                                  /\ writing, 
                                  "Failure of assertion at line 145, column 11.")
                        /\ writing' = FALSE
                        /\ IF Head(iocontext) = "write" /\ state = "Connected"
                              THEN /\ iocontext' = Tail(iocontext)
                                   /\ asyncRunning' = "read"
                                   /\ reading' = TRUE
                                   /\ alarm' = "readAlarm"
                                   /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                                   /\ UNCHANGED << state, stack >>
                              ELSE /\ iocontext' = Tail(iocontext)
                                   /\ alarm' = "off"
                                   /\ state' = "Failed"
                                   /\ stack' = [stack EXCEPT !["fuertethread"] = << [ procedure |->  "terminateActivity",
                                                                                      pc        |->  "loop" ] >>
                                                                                  \o stack["fuertethread"]]
                                   /\ pc' = [pc EXCEPT !["fuertethread"] = "terminateActivityBegin"]
                                   /\ UNCHANGED << asyncRunning, reading >>
                   ELSE /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                        /\ UNCHANGED << state, alarm, asyncRunning, iocontext, 
                                        reading, writing, stack >>
             /\ UNCHANGED << active, queueSize >>

readDone == /\ pc["fuertethread"] = "readDone"
            /\ IF /\ Len(iocontext) >= 1
                  /\ Head(iocontext) \in {"read", "readBAD"}
                  THEN /\ Assert(active /\ state \in {"Connected", "Disconnected", "Failed"}, 
                                 "Failure of assertion at line 165, column 11.")
                       /\ alarm' = "off"
                       /\ reading' = FALSE
                       /\ IF Head(iocontext) = "read" /\ state = "Connected"
                             THEN /\ iocontext' = Tail(iocontext)
                                  /\ stack' = [stack EXCEPT !["fuertethread"] = << [ procedure |->  "asyncWriteNextRequest",
                                                                                     pc        |->  "loop" ] >>
                                                                                 \o stack["fuertethread"]]
                                  /\ pc' = [pc EXCEPT !["fuertethread"] = "asyncWriteNextRequestBegin"]
                                  /\ state' = state
                             ELSE /\ iocontext' = Tail(iocontext)
                                  /\ state' = "Failed"
                                  /\ stack' = [stack EXCEPT !["fuertethread"] = << [ procedure |->  "terminateActivity",
                                                                                     pc        |->  "loop" ] >>
                                                                                 \o stack["fuertethread"]]
                                  /\ pc' = [pc EXCEPT !["fuertethread"] = "terminateActivityBegin"]
                  ELSE /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                       /\ UNCHANGED << state, alarm, iocontext, reading, stack >>
            /\ UNCHANGED << active, queueSize, asyncRunning, writing >>

cancellation == /\ pc["fuertethread"] = "cancellation"
                /\ IF /\ Len(iocontext) >= 1 /\ Head(iocontext) = "cancel"
                      THEN /\ iocontext' = Tail(iocontext)
                           /\ state' = "Failed"
                           /\ queueSize' = 0
                           /\ alarm' = "off"
                           /\ IF asyncRunning = "connect"
                                 THEN /\ asyncRunning' = "connectBAD"
                                 ELSE /\ IF asyncRunning = "write"
                                            THEN /\ asyncRunning' = "writeBAD"
                                            ELSE /\ IF asyncRunning = "read"
                                                       THEN /\ asyncRunning' = "readBAD"
                                                       ELSE /\ TRUE
                                                            /\ UNCHANGED asyncRunning
                      ELSE /\ TRUE
                           /\ UNCHANGED << state, queueSize, alarm, 
                                           asyncRunning, iocontext >>
                /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                /\ UNCHANGED << active, reading, writing, stack >>

alarmTriggered == /\ pc["fuertethread"] = "alarmTriggered"
                  /\ IF alarm /= "off"
                        THEN /\ iocontext' = Append(iocontext, alarm)
                             /\ alarm' = "off"
                        ELSE /\ TRUE
                             /\ UNCHANGED << alarm, iocontext >>
                  /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                  /\ UNCHANGED << state, active, queueSize, asyncRunning, 
                                  reading, writing, stack >>

asyncFinished == /\ pc["fuertethread"] = "asyncFinished"
                 /\ IF asyncRunning /= "none"
                       THEN /\ iocontext' = Append(iocontext, asyncRunning)
                            /\ asyncRunning' = "none"
                       ELSE /\ TRUE
                            /\ UNCHANGED << asyncRunning, iocontext >>
                 /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                 /\ UNCHANGED << state, active, queueSize, alarm, reading, 
                                 writing, stack >>

handleConnectAlarm == /\ pc["fuertethread"] = "handleConnectAlarm"
                      /\ IF Len(iocontext) >= 1 /\ Head(iocontext) = "connectAlarm"
                            THEN /\ iocontext' = Tail(iocontext)
                                 /\ IF asyncRunning = "connect"
                                       THEN /\ asyncRunning' = "connectBAD"
                                       ELSE /\ TRUE
                                            /\ UNCHANGED asyncRunning
                            ELSE /\ TRUE
                                 /\ UNCHANGED << asyncRunning, iocontext >>
                      /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                      /\ UNCHANGED << state, active, queueSize, alarm, reading, 
                                      writing, stack >>

handleWriteAlarm == /\ pc["fuertethread"] = "handleWriteAlarm"
                    /\ IF Len(iocontext) >= 1 /\ Head(iocontext) = "writeAlarm"
                          THEN /\ iocontext' = Tail(iocontext)
                               /\ IF writing /\ asyncRunning = "write"
                                     THEN /\ asyncRunning' = "writeBAD"
                                     ELSE /\ TRUE
                                          /\ UNCHANGED asyncRunning
                          ELSE /\ TRUE
                               /\ UNCHANGED << asyncRunning, iocontext >>
                    /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                    /\ UNCHANGED << state, active, queueSize, alarm, reading, 
                                    writing, stack >>

handleReadAlarm == /\ pc["fuertethread"] = "handleReadAlarm"
                   /\ IF Len(iocontext) >= 1 /\ Head(iocontext) = "readAlarm"
                         THEN /\ iocontext' = Tail(iocontext)
                              /\ IF reading /\ asyncRunning = "read"
                                    THEN /\ asyncRunning' = "readBAD"
                                    ELSE /\ TRUE
                                         /\ UNCHANGED asyncRunning
                         ELSE /\ TRUE
                              /\ UNCHANGED << asyncRunning, iocontext >>
                   /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                   /\ UNCHANGED << state, active, queueSize, alarm, reading, 
                                   writing, stack >>

handleIdleAlarm == /\ pc["fuertethread"] = "handleIdleAlarm"
                   /\ IF Len(iocontext) >= 1 /\ Head(iocontext) = "idleAlarm"
                         THEN /\ iocontext' = Tail(iocontext)
                              /\ IF ~ active /\ state = "Connected"
                                    THEN /\ state' = "Failed"
                                         /\ alarm' = "off"
                                         /\ stack' = [stack EXCEPT !["fuertethread"] = << [ procedure |->  "terminateActivity",
                                                                                            pc        |->  "loop" ] >>
                                                                                        \o stack["fuertethread"]]
                                         /\ pc' = [pc EXCEPT !["fuertethread"] = "terminateActivityBegin"]
                                    ELSE /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                                         /\ UNCHANGED << state, alarm, stack >>
                         ELSE /\ pc' = [pc EXCEPT !["fuertethread"] = "loop"]
                              /\ UNCHANGED << state, alarm, iocontext, stack >>
                   /\ UNCHANGED << active, queueSize, asyncRunning, reading, 
                                   writing >>

fuerte == loop \/ activate \/ connectDone \/ writeDone \/ readDone
             \/ cancellation \/ alarmTriggered \/ asyncFinished
             \/ handleConnectAlarm \/ handleWriteAlarm \/ handleReadAlarm
             \/ handleIdleAlarm

sendMessage == /\ pc["clientthread"] = "sendMessage"
               /\ queueSize < 2 /\ state /= "Failed"
               /\ pc' = [pc EXCEPT !["clientthread"] = "pushQueue"]
               /\ UNCHANGED << state, active, queueSize, alarm, asyncRunning, 
                               iocontext, reading, writing, stack >>

pushQueue == /\ pc["clientthread"] = "pushQueue"
             /\ queueSize' = queueSize + 1
             /\ pc' = [pc EXCEPT !["clientthread"] = "postActivate"]
             /\ UNCHANGED << state, active, alarm, asyncRunning, iocontext, 
                             reading, writing, stack >>

postActivate == /\ pc["clientthread"] = "postActivate"
                /\ IF ~ active
                      THEN /\ active' = TRUE
                           /\ iocontext' = Append(iocontext, "activate")
                      ELSE /\ TRUE
                           /\ UNCHANGED << active, iocontext >>
                /\ pc' = [pc EXCEPT !["clientthread"] = "sendMessage"]
                /\ UNCHANGED << state, queueSize, alarm, asyncRunning, reading, 
                                writing, stack >>

client == sendMessage \/ pushQueue \/ postActivate

cancelBegin == /\ pc["cancelthread"] = "cancelBegin"
               /\ iocontext' = Append(iocontext, "cancel")
               /\ pc' = [pc EXCEPT !["cancelthread"] = "Done"]
               /\ UNCHANGED << state, active, queueSize, alarm, asyncRunning, 
                               reading, writing, stack >>

cancel == cancelBegin

Next == fuerte \/ client \/ cancel
           \/ (\E self \in ProcSet:  \/ startConnection(self)
                                     \/ terminateActivity(self)
                                     \/ asyncWriteNextRequest(self))

Spec == Init /\ [][Next]_vars

\* END TRANSLATION

\* Invariants to prove:

TypeOK == /\ state \in {"Disconnected", "Connecting", "Connected", "Failed"}
          /\ active \in {FALSE, TRUE}
          /\ queueSize \in 0..2
          /\ alarm \in {"off", "connectAlarm", "writeAlarm", "readAlarm",
                        "idleAlarm"}
          /\ asyncRunning \in {"none", "connect", "connectBAD", "write",
                               "writeBAD", "read", "readBAD"}
          /\ reading \in {FALSE, TRUE}
          /\ writing \in {FALSE, TRUE}
          
(* When we are active, something has to be ongoing, either an async call, or
   something scheduled on the iocontext. However, there is the tiny moment when
   we are just about to start the connection anew, or when we are about to start
   a write operation. *)
WorkingIfActive == active => \/ asyncRunning /= "none"
                             \/ Len(iocontext) > 0
                             \/ pc["fuertethread"] = "startConnectionBegin"
                             \/ pc["fuertethread"] = "asyncWriteNextRequestBegin"
                             \/ pc["fuertethread"] = "check"
                             \/ pc["fuertethread"] = "deactivate"
                             \/ pc["fuertethread"] = "checkAgain"
                             \/ pc["fuertethread"] = "reactivate"
                             \/ pc["fuertethread"] = "drain"
                             \/ pc["fuertethread"] = "deactivate2"
                             \/ pc["fuertethread"] = "checkAgain2"
                             \/ pc["fuertethread"] = "reactivate2"
                             \/ pc["fuertethread"] = "pop"
                             \/ pc["fuertethread"] = "terminateActivityBegin"
                             \/ pc["fuertethread"] = "terminateLoop"
                             
(* We basically want to either have an empty queue or want to be active.
   There are very tiny moments in time when both are violated, one is
   exactly when a new message is on the queue but the fuerte thread is not
   yet reactivated. The other is, if the check-set-check pattern is between
   the set and the recheck. These are the pc exceptions we have to have here: *)
NothingForgottenOnQueue == \/ queueSize = 0
                           \/ active
                           \/ pc["clientthread"] = "postActivate"
                           \/ pc["fuertethread"] = "check"
                           \/ pc["fuertethread"] = "reactivate"
                           \/ pc["fuertethread"] = "checkAgain"
                           \/ pc["fuertethread"] = "drain"
                           \/ pc["fuertethread"] = "reactivate2"
                           \/ pc["fuertethread"] = "checkAgain2"
                           
NoSleepingBarber == /\ NothingForgottenOnQueue
                    /\ WorkingIfActive


=============================================================================
\* Modification History
\* Last modified Tue May 05 08:45:25 CEST 2020 by neunhoef
\* Created Mi 22. Apr 22:46:19 CEST 2020 by neunhoef
