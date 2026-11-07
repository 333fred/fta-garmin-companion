using Toybox.WatchUi as Ui;

class StatusViewDelegate extends Ui.InputDelegate {

    private var _ui;

    private var _currentState;
    private var _previousState;

    function initialize(ui) {
        _ui = ui;
        InputDelegate.initialize();
    }

    function onSwipe(swipeEvent) {
        var direction = swipeEvent.getDirection();
        switch (direction) {
            case Ui.SWIPE_UP:
            case Ui.SWIPE_DOWN:
                handleNumber();
                return true;
            case Ui.SWIPE_LEFT:
                handleBattery();
                return true;
        }

        return false;
    }

    function onKeyPressed(keyEvent) {
        if (keyEvent.getKey() == Ui.KEY_ENTER && _currentState != ViewStatus.FIELD_STATUS) {
            activateFieldStatus();
            return true;
        }

        return false;
    }

    function onKeyReleased(keyEvent) {
        if (keyEvent.getKey() == Ui.KEY_ENTER && _currentState == ViewStatus.FIELD_STATUS) {
            deactivateFieldStatus();
            return true;
        }

        return false;
    }

    function onHold(keyEvent) {
        if (_currentState != ViewStatus.FIELD_STATUS) {
            activateFieldStatus();
            return true;
        }
        return false;
    }

    function onTap(keyEvent) {
        if (_currentState == ViewStatus.FIELD_STATUS) {
            deactivateFieldStatus();
            return true;
        }
        return false;
    }

    private function activateFieldStatus() {
        _previousState = _currentState;
        _currentState = ViewStatus.FIELD_STATUS;
        _ui.setViewStatus(_currentState);
    }

    private function deactivateFieldStatus() {
        _currentState = _previousState;
        _ui.setViewStatus(_currentState);
    }

    function handleNumber() {
        handleState(ViewStatus.TEAM_NUMBER);
    }

    function handleBattery() {
        handleState(ViewStatus.BATTERY);
    }

    function handleState(targetState) {
        var state = _currentState == ViewStatus.FIELD_STATUS ? _previousState : _currentState;
        if (state == targetState) {
            state = ViewStatus.TEAM_STATUS;
        } else {
            state = targetState;
        }
        if (_currentState == ViewStatus.FIELD_STATUS) {
            _previousState = state;
        } else {
            _currentState = state;
            _ui.setViewStatus(_currentState);
        }
    }
}
