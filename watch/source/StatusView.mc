using Toybox.Attention as Attention;
using Toybox.Lang;
using Toybox.Graphics;
using Toybox.System;
using Toybox.WatchUi as Ui;

module ViewStatus {
    enum {
        TEAM_STATUS,
        TEAM_NUMBER,
        BATTERY,
        FIELD_STATUS
    }
}

class StatusView extends Ui.View {
    // Device dimensions
    private var _deviceWidth;
    private var _deviceHeight;

    // Views
    private var _timeView;
    private var _batteryView;
    private var _lastTime;
    private var _matchStatus;
    private var _blueHeader;
    private var _redHeader;
    private var _blue1Text;
    private var _blue2Text;
    private var _blue3Text;
    private var _red1Text;
    private var _red2Text;
    private var _red3Text;
    private var _matchTitleText;
    private var _matchNumberText;
    private var _matchTimeText;

    // Highlight status
    private var _blue1Highlight = true;
    private var _blue2Highlight = true;
    private var _blue3Highlight = true;
    private var _red1Highlight = true;
    private var _red2Highlight = true;
    private var _red3Highlight = true;

    // Cell positions
    private var _thirdRowBackgroundYStart;
    private var _thirdRowHeight;
    private var _cellHeight;
    private var _cell1YStart;
    private var _cell1YEnd;
    private var _cell2YStart;
    private var _cell2YEnd;
    private var _cell3YStart;
    private var _cell3YEnd;
    private var _cellWidth;
    private var _radius = 3;
    private var _blueCellStart;
    private var _redCellStart;

    // Status of things
    private var _teamStatus;
    // ViewStatus.TEAM_STATUS/TEAM_NUMBER/BATTERY
    private var _displayStatus;

    function initialize(teamStatus) {
        View.initialize();
        _teamStatus = teamStatus;
        _displayStatus = ViewStatus.TEAM_STATUS;
    }

    // Load your resources here
    function onLayout(dc) {
        _deviceWidth = dc.getWidth();
        _deviceHeight = dc.getHeight();

        // The heights of the text we need to do math on.
        var xTinyHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var xTinyHeightOffset= (xTinyHeight / 2).toNumber();
        var tinyHeight = dc.getFontHeight(Graphics.FONT_TINY);
        var tinyHeightOffset = (tinyHeight / 2).toNumber();

        // Top Marging
        var margin = 2;
        var firstRowY = margin + xTinyHeightOffset;
        var secondRowStart = 1 + xTinyHeight;
        var secondRowY = secondRowStart + tinyHeightOffset;
        _thirdRowBackgroundYStart = secondRowStart + tinyHeight + margin;
        var thirdRowY = _thirdRowBackgroundYStart + tinyHeightOffset;
        var thirdRowBackgroundYEnd = _thirdRowBackgroundYStart + tinyHeight + 1;
        _thirdRowHeight = thirdRowBackgroundYEnd - _thirdRowBackgroundYStart;

        // Height to split among the rest of the cells
        var gridHeight = _deviceHeight - thirdRowBackgroundYEnd - 1;
        _cellHeight = (gridHeight / 3).toNumber() - 2;
        var cellTextOffset = (_cellHeight / 2).toNumber();

        _cell1YStart = thirdRowBackgroundYEnd + 2;
        _cell1YEnd = _cell1YStart + _cellHeight;
        var cell1Text = _cell1YStart + cellTextOffset;

        _cell2YStart = _cell1YEnd + 2;
        _cell2YEnd = _cell2YStart + _cellHeight;
        var cell2Text = _cell2YStart + cellTextOffset;

        _cell3YStart = _cell2YEnd + 2;
        _cell3YEnd = _cell3YStart + _cellHeight;
        var screenSquare = System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_RECTANGLE;
        var cell3Text = _cell3YStart + (screenSquare ? cellTextOffset : cellTextOffset - 5);

        var blueJustification = (screenSquare ? Graphics.TEXT_JUSTIFY_CENTER : Graphics.TEXT_JUSTIFY_LEFT) | Graphics.TEXT_JUSTIFY_VCENTER;
        var redJustification = (screenSquare ? Graphics.TEXT_JUSTIFY_CENTER : Graphics.TEXT_JUSTIFY_RIGHT) | Graphics.TEXT_JUSTIFY_VCENTER;
        var totallyCentered = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Split the X dimension into quarters, the numbers
        // will be set on the dividers between the quarters
        var halfWidth = (_deviceWidth / 2).toNumber();
        _blueCellStart = 2;
        _redCellStart = halfWidth + 1;
        _cellWidth = halfWidth - 3;

        // 1/4 of the screen on left
        var leftCentered = (halfWidth / 2).toNumber();
        // 3/4 of the screen on the right
        var rightCentered = halfWidth + leftCentered;

        var cellFont = screenSquare ? Graphics.FONT_MEDIUM : Graphics.FONT_TINY;

        _timeView = new Ui.Text({
            :color=>Graphics.COLOR_WHITE,
            :font=>Graphics.FONT_XTINY,
            :justification=>(screenSquare ? Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER : totallyCentered),
            :locX=>(screenSquare ? margin : halfWidth),
            :locY=>firstRowY
        });

        _batteryView = new Ui.Text({
            :color=>Graphics.COLOR_WHITE,
            :font=>Graphics.FONT_XTINY,
            :justification=>Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER,
            :locX=>_deviceWidth - margin,
            :locY=>firstRowY
        });

        _matchStatus = new Ui.Text({
            :color=>Graphics.COLOR_WHITE,
            :font=>Graphics.FONT_TINY,
            :justification=>totallyCentered,
            :locX=>halfWidth,
            :locY=>secondRowY
        });

        _blueHeader = new Ui.Text({
            :text=>"Blue",
            :color=>Graphics.COLOR_WHITE,
            :font=>Graphics.FONT_TINY,
            :justification=>blueJustification,
            :locX=>leftCentered,
            :locY=>thirdRowY
        });

        _redHeader = new Ui.Text({
            :text=>"Red",
            :color=>Graphics.COLOR_WHITE,
            :font=>Graphics.FONT_TINY,
            :justification=>redJustification,
            :locX=>rightCentered,
            :locY=>thirdRowY
        });

        _blue1Text = new Ui.Text({
            :color=>Graphics.COLOR_WHITE,
            :font=>cellFont,
            :justification=>blueJustification,
            :locX=>leftCentered,
            :locY=>cell1Text
        });

        _blue2Text = new Ui.Text({
            :color=>Graphics.COLOR_WHITE,
            :font=>cellFont,
            :justification=>blueJustification,
            :locX=>leftCentered,
            :locY=>cell2Text
        });

        _blue3Text = new Ui.Text({
            :color=>Graphics.COLOR_WHITE,
            :font=>cellFont,
            :justification=>blueJustification,
            :locX=>leftCentered,
            :locY=>cell3Text
        });

        _red1Text = new Ui.Text({
            :color=>Graphics.COLOR_WHITE,
            :font=>cellFont,
            :justification=>redJustification,
            :locX=>rightCentered,
            :locY=>cell3Text
        });

        _red2Text = new Ui.Text({
            :color=>Graphics.COLOR_WHITE,
            :font=>cellFont,
            :justification=>redJustification,
            :locX=>rightCentered,
            :locY=>cell2Text
        });

        _red3Text = new Ui.Text({
            :color=>Graphics.COLOR_WHITE,
            :font=>cellFont,
            :justification=>redJustification,
            :locX=>rightCentered,
            :locY=>cell1Text
        });


        // Calculate the position of the field info text boxes
        var midGrid = ((_deviceHeight - _thirdRowBackgroundYStart) / 2).toNumber() + _thirdRowBackgroundYStart;
        var largeTextHeight = dc.getFontHeight(Graphics.FONT_LARGE);
        var largeHeightOffset = (largeTextHeight / 2).toNumber();

        _matchTitleText = new Ui.Text({
            :text=>"Match Number",
            :font=>Graphics.FONT_MEDIUM,
            :color=>Graphics.COLOR_WHITE,
            :justification=>totallyCentered,
            :locX=>halfWidth,
            :locY=>(midGrid - largeTextHeight - margin)
        });
        _matchNumberText= new Ui.Text({
            :text=>"Pratice 999",
            :font=>Graphics.FONT_LARGE,
            :color=>Graphics.COLOR_WHITE,
            :justification=>totallyCentered,
            :locX=>halfWidth,
            :locY=>midGrid
        });
        _matchTimeText= new Ui.Text({
            :text=>"+1",
            :font=>Graphics.FONT_TINY,
            :color=>Graphics.COLOR_WHITE,
            :justification=>totallyCentered,
            :locX=>halfWidth,
            :locY=>(midGrid + largeHeightOffset + margin + tinyHeightOffset)
        });

        updateTimeAndBattery();
        updateTeams();
        drawUi(dc);
    }

    // Update the view
    function onUpdate(dc) {
        // Call the parent onUpdate function to redraw the layout
        updateTimeAndBattery();
        updateTeams();
        drawUi(dc);
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() {
    }

    function vibrate() {
        if (Attention has :vibrate) {
            var vibrateData = [
                    new Attention.VibeProfile(50, 500),
                ];
            Attention.vibrate(vibrateData);
        } else {
            System.println("Vibe not supported");
        }
    }

    public function setViewStatus(status) {
        _displayStatus = status;
        Ui.requestUpdate();
    }

    private function updateTimeAndBattery() {
        var currentTime = System.getClockTime();
        var timeString = currentTime.hour.format("%02d") + ":" + currentTime.min.format("%02d");
        _timeView.setText(timeString);
        _batteryView.setText(System.getSystemStats().battery.format("%.0f") + "%");
        _matchStatus.setText(MatchState.getStatusString(_teamStatus.MatchStatus));
    }

    private function updateTeams() {
        if (_displayStatus == ViewStatus.TEAM_STATUS) {
            _blue1Highlight = TeamStatus.isBadStatus(_teamStatus.Blue1Status);
            _blue1Text.setText(TeamStatus.getStatusString(_teamStatus.Blue1Status));
            _blue2Highlight = TeamStatus.isBadStatus(_teamStatus.Blue2Status);
            _blue2Text.setText(TeamStatus.getStatusString(_teamStatus.Blue2Status));
            _blue3Highlight = TeamStatus.isBadStatus(_teamStatus.Blue3Status);
            _blue3Text.setText(TeamStatus.getStatusString(_teamStatus.Blue3Status));
            _red1Highlight = TeamStatus.isBadStatus(_teamStatus.Red1Status);
            _red1Text.setText(TeamStatus.getStatusString(_teamStatus.Red1Status));
            _red2Highlight = TeamStatus.isBadStatus(_teamStatus.Red2Status);
            _red2Text.setText(TeamStatus.getStatusString(_teamStatus.Red2Status));
            _red3Highlight = TeamStatus.isBadStatus(_teamStatus.Red3Status);
            _red3Text.setText(TeamStatus.getStatusString(_teamStatus.Red3Status));
        } else if (_displayStatus == ViewStatus.TEAM_NUMBER) {
            _blue1Text.setText(_teamStatus.Blue1Number.format("%d"));
            _blue2Text.setText(_teamStatus.Blue2Number.format("%d"));
            _blue3Text.setText(_teamStatus.Blue3Number.format("%d"));
            _red1Text.setText(_teamStatus.Red1Number.format("%d"));
            _red2Text.setText(_teamStatus.Red2Number.format("%d"));
            _red3Text.setText(_teamStatus.Red3Number.format("%d"));
        } else {
            _blue1Text.setText(TeamStatus.formatBattery(_teamStatus.Blue1Battery));
            _blue2Text.setText(TeamStatus.formatBattery(_teamStatus.Blue2Battery));
            _blue3Text.setText(TeamStatus.formatBattery(_teamStatus.Blue3Battery));
            _red1Text.setText(TeamStatus.formatBattery(_teamStatus.Red1Battery));
            _red2Text.setText(TeamStatus.formatBattery(_teamStatus.Red2Battery));
            _red3Text.setText(TeamStatus.formatBattery(_teamStatus.Red3Battery));
        }
    }

    private function updateFieldStatus() {
        // TODO: Implement
    }

    private function drawUi(dc) {
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_BLACK);
        dc.clear();

        // Redraw the headers
        _matchStatus.draw(dc);
        _timeView.draw(dc);
        _batteryView.draw(dc);

        if (_displayStatus != ViewStatus.FIELD_STATUS) {
            // Blue side
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_BLACK);
            dc.fillRoundedRectangle(_blueCellStart, _thirdRowBackgroundYStart, _cellWidth, _thirdRowHeight, _radius);
            setColors(dc, true, _blue1Highlight, _blue1Text);
            dc.fillRoundedRectangle(_blueCellStart, _cell1YStart, _cellWidth, _cellHeight, _radius);
            setColors(dc, true, _blue2Highlight, _blue2Text);
            dc.fillRoundedRectangle(_blueCellStart, _cell2YStart, _cellWidth, _cellHeight, _radius);
            setColors(dc, true, _blue3Highlight, _blue3Text);
            dc.fillRoundedRectangle(_blueCellStart, _cell3YStart, _cellWidth, _cellHeight, _radius);

            // Red side
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
            dc.fillRoundedRectangle(_redCellStart, _thirdRowBackgroundYStart, _cellWidth, _thirdRowHeight, _radius);
            setColors(dc, false, _red1Highlight, _red1Text);
            dc.fillRoundedRectangle(_redCellStart, _cell3YStart, _cellWidth, _cellHeight, _radius);
            setColors(dc, false, _red2Highlight, _red2Text);
            dc.fillRoundedRectangle(_redCellStart, _cell2YStart, _cellWidth, _cellHeight, _radius);
            setColors(dc, false, _red3Highlight, _red3Text);
            dc.fillRoundedRectangle(_redCellStart, _cell1YStart, _cellWidth, _cellHeight, _radius);

            updateTeams();
            _blue1Text.draw(dc);
            _blue2Text.draw(dc);
            _blue3Text.draw(dc);
            _red1Text.draw(dc);
            _red2Text.draw(dc);
            _red3Text.draw(dc);
            _blueHeader.setText(Rez.Strings.blue);
            _blueHeader.draw(dc);
            _redHeader.setText(Rez.Strings.red);
            _redHeader.draw(dc);
        } else {
            updateFieldStatus();
            _matchTitleText.draw(dc);
            _matchNumberText.draw(dc);
            _matchTimeText.draw(dc);
        }
    }

    private function setColors(dc, isBlue, highlight, textBox) {
        if (highlight) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            textBox.setColor(isBlue ? Graphics.COLOR_BLUE : Graphics.COLOR_RED);
        } else {
            dc.setColor(isBlue ? Graphics.COLOR_BLUE : Graphics.COLOR_RED, Graphics.COLOR_BLACK);
            textBox.setColor(Graphics.COLOR_WHITE);
        }
    }
}
