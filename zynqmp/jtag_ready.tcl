proc jtag_ready {hw_ip} {
#connect
    if {$hw_ip eq "" || $hw_ip eq "local"} {
        connect
    } else {
        connect -url tcp:$hw_ip:3121
    }

    set retry 0
    while {$retry < 25} {
        if {[string first "closed" "[jtag targets]"] != -1} {
            after 100
            incr retry
        } else {
            break
        }
    }
}