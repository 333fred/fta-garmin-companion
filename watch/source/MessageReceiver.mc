using Toybox.WatchUi as Ui;
using Toybox.Application as App;

class MessageReceiver {

    private var _teamStatus;

    public function initialize(teamStatus) {
        _teamStatus = teamStatus;
    }

    public function receive(message) {
        var dict = message.data;
        var keys = dict.keys();
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i];
            var value = dict[key];
            switch (key) {
                case RED1_STATUS:
                    _teamStatus.Red1Status = value;
                    break;
                case RED2_STATUS:
                    _teamStatus.Red2Status = value;
                    break;
                case RED3_STATUS:
                    _teamStatus.Red3Status = value;
                    break;
                case BLUE1_STATUS:
                    _teamStatus.Blue1Status = value;
                    break;
                case BLUE2_STATUS:
                    _teamStatus.Blue2Status = value;
                    break;
                case BLUE3_STATUS:
                    _teamStatus.Blue3Status = value;
                    break;
                case RED1_NUMBER:
                    _teamStatus.Red1Number = value;
                    break;
                case RED2_NUMBER:
                    _teamStatus.Red2Number = value;
                    break;
                case RED3_NUMBER:
                    _teamStatus.Red3Number = value;
                    break;
                case BLUE1_NUMBER:
                    _teamStatus.Blue1Number = value;
                    break;
                case BLUE2_NUMBER:
                    _teamStatus.Blue2Number = value;
                    break;
                case BLUE3_NUMBER:
                    _teamStatus.Blue3Number = value;
                    break;
                case RED1_BATT:
                    _teamStatus.Red1Battery = value;
                    break;
                case RED2_BATT:
                    _teamStatus.Red2Battery = value;
                    break;
                case RED3_BATT:
                    _teamStatus.Red3Battery = value;
                    break;
                case BLUE1_BATT:
                    _teamStatus.Blue1Battery = value;
                    break;
                case BLUE2_BATT:
                    _teamStatus.Blue2Battery = value;
                    break;
                case BLUE3_BATT:
                    _teamStatus.Blue3Battery = value;
                    break;
                case VIBE:
                    App.getApp().vibrate();
                    break;
                case MATCH_STATE:
                    _teamStatus.MatchStatus = value;
                    break;
            }
        }

        Ui.requestUpdate();
    }
}

// Different message keys
enum {
    RED1_STATUS = 1,
    RED2_STATUS = 2,
    RED3_STATUS = 3,
    BLUE1_STATUS = 4,
    BLUE2_STATUS = 5,
    BLUE3_STATUS = 6,
    VIBE = 7,
    UPDATE = 8,
    RED1_NUMBER = 9,
    RED2_NUMBER = 10,
    RED3_NUMBER = 11,
    BLUE1_NUMBER = 12,
    BLUE2_NUMBER = 13,
    BLUE3_NUMBER = 14,
    RED1_BATT = 15,
    RED2_BATT = 16,
    RED3_BATT = 17,
    BLUE1_BATT = 18,
    BLUE2_BATT = 19,
    BLUE3_BATT = 20,
    MATCH_STATE = 21
}
