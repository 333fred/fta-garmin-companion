using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications;
using Toybox.Timer;

class FtaMonitorApp extends App.AppBase {

    private var _timer;
    private var _teamStatus;
    private var _messageReceiver;
    private var _view;

    function initialize() {
        AppBase.initialize();
        _teamStatus = new TeamStatusManager();
        _messageReceiver = new MessageReceiver(_teamStatus);
    }

    // onStart() is called on application start up
    function onStart(state) {
        _timer = new Timer.Timer();
        Communications.registerForPhoneAppMessages(_messageReceiver.method(:receive));
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function vibrate() {
        // Possible to be null if the app has just started up and there are messages queued, then
        // the view won't yet be created so we won't be able to vibrate.
        if (_view != null) {
            _view.vibrate();
        }
    }

    // Return the initial view of your application here
    function getInitialView() {
        _view = new StatusView(_teamStatus);
        var viewArray = [ _view, new StatusViewDelegate(_view) ];
        _timer.start(new Lang.Method(Ui, :requestUpdate), 60000, true);
        return viewArray;
    }
}
