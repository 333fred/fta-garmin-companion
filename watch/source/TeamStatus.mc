using Toybox.System;

class TeamStatusManager {
    // All variables are of type TeamStatus
    public var Blue1Status;
    public var Blue2Status;
    public var Blue3Status;
    public var Red1Status;
    public var Red2Status;
    public var Red3Status;

    public var Blue1Number;
    public var Blue2Number;
    public var Blue3Number;
    public var Red1Number;
    public var Red2Number;
    public var Red3Number;

    public var Blue1Battery;
    public var Blue2Battery;
    public var Blue3Battery;
    public var Red1Battery;
    public var Red2Battery;
    public var Red3Battery;

    // Of type MatchState
    public var MatchStatus;

    function initialize() {
        Blue1Status = TeamStatus.ETH;
        Blue2Status = TeamStatus.ETH;
        Blue3Status = TeamStatus.ETH;
        Red1Status = TeamStatus.ETH;
        Red2Status = TeamStatus.ETH;
        Red3Status = TeamStatus.ETH;

        Blue1Number = 1;
        Blue2Number = 2;
        Blue3Number = 3;
        Red1Number = 4;
        Red2Number = 5;
        Red3Number = 6;

        Blue1Battery = 11.11;
        Blue2Battery = 22.22;
        Blue3Battery = 33.33;
        Red1Battery = 44.44;
        Red2Battery = 55.55;
        Red3Battery = 66.66;

        MatchStatus = MatchState.NOT_READY;
    }
}

module MatchState {
    enum {
        NOT_READY=0,
        TIMEOUT=1,
        READY_PRESTART=2,
        PRESTART_INITATED=3,
        PRESTART_COMPLETED=4,
        MATCH_READY=5,
        SENDING_DATA=6,
        AUTO=7,
        TRANSITION=8,
        TELEOP=9,
        OVER=10,
        ABORTED=11
    }

    function getStatusString(status) {
        switch (status) {
            case NOT_READY:
                return Rez.Strings.not_ready;
            case TIMEOUT:
                return Rez.Strings.timeout;
            case READY_PRESTART:
                return Rez.Strings.ready_prestart;
            case PRESTART_INITATED:
                return Rez.Strings.prestart_initiated;
            case PRESTART_COMPLETED:
                return Rez.Strings.prestart_completed;
            case MATCH_READY:
                return Rez.Strings.match_ready;
            case SENDING_DATA:
                return Rez.Strings.sending_data;
            case AUTO:
                return Rez.Strings.auto_mode;
            case TRANSITION:
                return Rez.Strings.transition_mode;
            case TELEOP:
                return Rez.Strings.teleop_mode;
            case OVER:
                return Rez.Strings.over;
            case ABORTED:
                return Rez.Strings.aborted;
            default:
                return "";
        }
    }
}

module TeamStatus {
    enum {
        ETH = 0,
        DS = 1,
        RADIO = 2,
        RIO = 3,
        CODE = 4,
        ESTOP = 5,
        GOOD = 6,
        BWU = 7,
        BYP = 8,
        BAT = 9,
        BAT_CONNECTED = 10
    }

    function getStatusString(status) {
        switch (status) {
            case ETH:
                return Rez.Strings.ethernet;
            case DS:
                return Rez.Strings.driverstation;
            case RADIO:
                return Rez.Strings.radio;
            case RIO:
                return Rez.Strings.rio;
            case CODE:
                return Rez.Strings.code;
            case ESTOP:
                return Rez.Strings.estop;
            case GOOD:
                return Rez.Strings.good;
            case BWU:
                return Rez.Strings.bandwidth;
            case BYP:
                return Rez.Strings.bypassed;
            case BAT:
            case BAT_CONNECTED:
                return Rez.Strings.battery;
            default:
                return "";
        }
    }

    function isBadStatus(status) {
        return status != GOOD && status != BAT_CONNECTED;
    }

    function formatBattery(battery) {
        return battery.format("%4.2f");
    }
}
