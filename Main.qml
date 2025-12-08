import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

ApplicationWindow {
    id: window
    visible: true
    width: 1280
    height: 720
    title: "주식 투자 시뮬레이션 게임"
    color: "#1e1e1e"

    // --- 색상 정의 ---
    readonly property color colorUp: "#ff4d4d"   // 상승 (빨강)
    readonly property color colorDown: "#4da6ff" // 하락 (파랑)
    readonly property color colorSame: "#aaaaaa" // 보합 (회색)

    // --- C++ Backend 데이터 ---
    property int day: backend.day
    property int maxDay: backend.maxDay
    property double cash: backend.cash
    property double totalAsset: backend.totalAsset
    property double prevAsset: backend.prevAsset

    property string newsTitle: backend.newsTitle
    property string newsBody: backend.newsBody

    // --- 데이터 모델 ---
    ListModel { id: stockModel }

    // 데이터 변경 감지
    Connections {
        target: backend
        function onDataChanged() { updateStockList() }

        function onNewsChanged() {
            newsHistoryModel.append({
                // [수정] 날짜 UI와 싱크를 맞추기 위해 -1 보정
                dayIdx: backend.day - 1,
                title: backend.newsTitle,
                body: backend.newsBody
            })
        }

        function onGameOver(isVictory, message) {
            gameOverPopup.isVictory = isVictory
            gameOverPopup.messageText = message
            gameOverPopup.open()
        }
    }

    function updateStockList() {
        var list = backend.stockList
        stockModel.clear()
        for(var i=0; i<list.length; i++) {
            stockModel.append(list[i])
        }
    }

    Component.onCompleted: updateStockList()

    // 뉴스 히스토리 모델
    ListModel {
        id: newsHistoryModel
        // 초기 상태는 0일차로 표기 or 시작 전 메시지
        ListElement { dayIdx: 0; title: "사전 브리핑"; body: "주식 시장 개장을 준비 중입니다." }
    }

    // --- 화면 1: 메인 메뉴 ---
    Rectangle {
        id: mainScreen
        anchors.fill: parent
        visible: true
        z: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0f2027" }
            GradientStop { position: 1.0; color: "#2c5364" }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 50
            Text {
                text: "주식\n시뮬레이션"
                font.pixelSize: 64; font.bold: true; color: window.colorUp
                horizontalAlignment: Text.AlignHCenter
                style: Text.Outline; styleColor: "black"
            }
            Button {
                text: "게임 시작"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 250; Layout.preferredHeight: 60
                background: Rectangle {
                    color: parent.down ? window.colorUp : "transparent"
                    border.color: window.colorUp; border.width: 2; radius: 30
                }
                contentItem: Text {
                    text: parent.text; color: parent.down ? "white" : window.colorUp
                    font.pixelSize: 24; font.bold: true
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    // 게임 시작 시 바로 1일차로 넘어가며 이벤트 발생
                    backend.nextTurn()
                    mainScreen.visible = false;
                    gameScreen.visible = true
                }
            }
        }
    }

    // --- 화면 2: 게임 화면 ---
    Item {
        id: gameScreen
        anchors.fill: parent
        visible: false

        // 상단 정보 바
        Rectangle {
            id: topBar
            height: 60; width: parent.width; color: "#2c2c2c"
            RowLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 30
                //  날짜를 (현재 backend.day - 1)로 표시하여 0일차부터 시작하는 느낌 구현
                Text { text: "📅 DAY " + (window.day - 1) + " / " + window.maxDay; color: "white"; font.pixelSize: 18; font.bold: true }
                Text { text: "💵 현금 " + window.cash.toLocaleString(Qt.locale(), 'f', 0) + " 원"; color: "#aaa"; font.pixelSize: 18 }
                Text { text: "💎 자산 " + window.totalAsset.toLocaleString(Qt.locale(), 'f', 0) + " 원"; color: "#aaa"; font.pixelSize: 18 }
                Item { Layout.fillWidth: true }
                Text { text: "목표: " + backend.goalAmount.toLocaleString(Qt.locale(), 'f', 0) + " 원"; color: "#ff9800"; font.pixelSize: 16 }
            }
        }

        RowLayout {
            anchors.top: topBar.bottom; anchors.bottom: bottomBar.top
            anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: 20; spacing: 20

            // (왼쪽) 주식 리스트
            Rectangle {
                Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 2
                color: "#2c2c2c"; radius: 10; border.color: "#333"
                Text {
                    text: "📈 MARKET LIST"
                    color: "white"; font.bold: true; font.pixelSize: 18
                    anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 20
                }
                GridView {
                    id: stockGrid
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.topMargin: 60; anchors.margins: 20
                    cellWidth: 160; cellHeight: 120
                    model: stockModel; clip: true
                    delegate: Rectangle {
                        width: 140; height: 100
                        color: mouseArea.containsMouse ? "#3e3e3e" : "#333"
                        radius: 8
                        border.color: mouseArea.containsMouse ? (model.changeRate >= 0 ? window.colorUp : window.colorDown) : "#444"
                        border.width: mouseArea.containsMouse ? 2 : 1
                        Column {
                            anchors.centerIn: parent; spacing: 8
                            Text { text: model.name; color: "white"; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                            Text {
                                text: model.price.toLocaleString(Qt.locale(), 'f', 0)
                                color: model.changeRate > 0 ? window.colorUp : (model.changeRate < 0 ? window.colorDown : window.colorSame)
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: (model.changeRate > 0 ? "▲" : (model.changeRate < 0 ? "▼" : "-")) + " " + Math.abs(model.changeRate).toFixed(1) + "%"
                                color: model.changeRate > 0 ? window.colorUp : (model.changeRate < 0 ? window.colorDown : window.colorSame)
                                font.pixelSize: 12; anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                        Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 5
                                width: ownedText.contentWidth + 10
                                height: 20
                                color: "#ff9800" // 잘 보이도록 주황색 배경
                                radius: 10
                                visible: model.owned > 0 // 보유량이 0보다 클 때만 보임
                        Text {
                            id: ownedText
                            anchors.centerIn: parent
                            text: model.owned + "주"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: mouseArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                tradeModal.stockIndex = index
                                tradeModal.stockName = model.name
                                tradeModal.stockPrice = model.price
                                tradeModal.stockOwned = model.owned
                                tradeModal.description = model.description
                                tradeModal.priceHistory = backend.getStockHistory(index)
                                tradeModal.tradeAmount = 1 // 팝업 열 때 1로 초기화
                                tradeModal.open()
                            }
                        }
                    }
                }
            }

            // (오른쪽) 뉴스 영역
            Rectangle {
                id: newsCard
                Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 1
                color: "#f4f1ea"; radius: 2
                border.color: newsMouseArea.containsMouse ? "#ff9800" : "transparent"
                border.width: newsMouseArea.containsMouse ? 2 : 0
                MouseArea {
                    id: newsMouseArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: newsDetailPopup.open()
                }
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 20; spacing: 10
                    Text { text: "DAILY NEWS"; color: "#1a1a1a"; font.family: "Times New Roman"; font.pixelSize: 28; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                    Text { text: "(클릭해서 전체보기)"; color: "#555"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                    Rectangle { height: 2; color: "black"; Layout.fillWidth: true }
                    Text { text: window.newsTitle; color: "#1a1a1a"; font.bold: true; font.pixelSize: 20; Layout.topMargin: 10 }
                    Text { text: window.newsBody; color: "#333"; font.pixelSize: 16; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.fillHeight: true; elide: Text.ElideRight }
                }
            }
        }

        // 하단 버튼 바
        Rectangle {
            id: bottomBar
            height: 80; width: parent.width; anchors.bottom: parent.bottom; color: "#111111"
            Button {
                id: nextDayBtn
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 30
                width: 250; height: 50
                background: Rectangle {
                    gradient: Gradient { GradientStop { position: 0.0; color: "#ff9800" } GradientStop { position: 1.0; color: "#ff5722" } }
                    radius: 5
                }
                contentItem: Row {
                    anchors.centerIn: parent; spacing: 10
                    Text { text: "🌙"; font.pixelSize: 20; Layout.alignment: Qt.AlignCenter}
                    Text { text: "하루 마감 및 정산"; color: "white"; font.bold: true; font.pixelSize: 16;Layout.alignment: Qt.AlignCenter }
                }
                onClicked: {
                    if (day > window.maxDay) return;
                    loadingOverlay.visible = true
                    simulationTimer.start()
                }
            }
        }
    }

    // --- 주식 거래 팝업 (차트 및 버튼 수정됨) ---
    Popup {
        id: tradeModal
        anchors.centerIn: parent; width: 600; height: 600
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property int stockIndex: -1
        property string stockName: ""
        property double stockPrice: 0
        property int stockOwned: 0
        property var priceHistory: []
        property int tradeAmount: 1
        property string description: ""

        background: Rectangle { color: "#2c2c2c"; border.color: "#555"; radius: 10 }
        contentItem: Item {
            anchors.fill: parent
            Button {
                text: "✕"; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                width: 40; height: 40; background: Rectangle { color: "transparent" }
                contentItem: Text { text: "✕"; color: "#aaa"; font.pixelSize: 24; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: tradeModal.close()
            }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 25; spacing: 15
                Text { text: tradeModal.stockName; color: "white"; font.pixelSize: 24; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                Text { text: tradeModal.description; color: "white"; font.pixelSize: 18; Layout.alignment: Qt.AlignCenter; wrapMode:Text.WordWrap
                Layout.fillWidth: true;Layout.maximumWidth: parent.width -50}
                // 차트 영역
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 250; color: "#222"; border.color: "#444"; clip: true
                    Canvas {
                        id: stockChart; anchors.fill: parent; antialiasing: true
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            var data = tradeModal.priceHistory;
                            if (!data || data.length < 1) {
                                ctx.fillStyle = "#aaa"; ctx.textAlign = "center"; ctx.fillText("데이터 부족", width/2, height/2); return;
                            }
                            var padLeft=45, padRight=30, padTop=30, padBottom=30;
                            var graphW = width - padLeft - padRight;
                            var graphH = height - padTop - padBottom;
                            var minVal = data[0], maxVal = data[0];
                            for (var i=1; i<data.length; i++) { if(data[i]<minVal) minVal=data[i]; if(data[i]>maxVal) maxVal=data[i]; }
                            var range = maxVal - minVal;
                            if (range === 0) { range = maxVal * 0.1; minVal -= range; maxVal += range; range = maxVal - minVal; }
                            else { var buffer = range * 0.1; minVal -= buffer; maxVal += buffer; range = maxVal - minVal; }

                            ctx.lineWidth = 1; ctx.strokeStyle = "#444"; ctx.beginPath();
                            ctx.moveTo(padLeft, padTop); ctx.lineTo(padLeft, height - padBottom); ctx.lineTo(width - padRight, height - padBottom); ctx.stroke();

                            ctx.beginPath(); ctx.lineWidth = 2; ctx.strokeStyle = window.colorUp;
                            var stepX = (data.length > 1) ? graphW / (data.length - 1) : graphW;
                            for (var j=0; j<data.length; j++) {
                                var x = padLeft + (j * stepX);
                                var y = (height - padBottom) - ((data[j] - minVal) / range) * graphH;
                                if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                            }
                            ctx.stroke();

                            ctx.font = "12px sans-serif";
                            for (var k=0; k<data.length; k++) {
                                var px = padLeft + (k * stepX);
                                var pVal = data[k];
                                var py = (height - padBottom) - ((pVal - minVal) / range) * graphH;
                                ctx.beginPath(); ctx.arc(px, py, 3, 0, 2*Math.PI); ctx.fillStyle = window.colorUp; ctx.fill();
                                if (k === 0) ctx.textAlign = "left"; else if (k === data.length - 1) ctx.textAlign = "right"; else ctx.textAlign = "center";
                                ctx.fillStyle = "#fff";
                                ctx.fillText(pVal.toFixed(0), px, py - 10);
                                ctx.fillStyle = "#aaa";

                                // 현재 화면에 표시되는 날짜(window.day - 1)를 기준으로 역산하여 차트 라벨을 매칭
                                var currentVisualDay = window.day - 1;
                                var dayLabelVal = currentVisualDay - (data.length - 1) + k;
                                var dayLabel = "D" + dayLabelVal;

                                ctx.fillText(dayLabel, px, height - padBottom + 15);
                            }
                        }
                    }
                    Connections { target: tradeModal; function onPriceHistoryChanged() { stockChart.requestPaint(); } }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "현재가: " + tradeModal.stockPrice.toLocaleString(Qt.locale(), 'f', 0); color: window.colorUp; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Text { text: "보유: " + tradeModal.stockOwned + "주"; color: "#aaa" }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#444" }

                // [수정] 수량 조절 (+ - 버튼 추가) 및 최대 버튼
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Text { text: "수량:"; color: "white"; font.pixelSize: 16 }

                    // [-] 버튼
                    Button {
                        text: "-"; width: 40; height: 40
                        background: Rectangle { color: "#444"; radius: 4 }
                        contentItem: Text { text: "-"; color: "white"; font.bold: true; font.pixelSize: 20; anchors.centerIn: parent }
                        onClicked: amountSpin.decrease()
                    }

                    SpinBox {
                        id: amountSpin
                        from: 1; to: 9999999
                        value: tradeModal.tradeAmount
                        editable: true
                        Layout.preferredWidth: 100
                        onValueChanged: tradeModal.tradeAmount = value

                        background: Rectangle { color: "#333"; border.color: "#555"; radius: 4 }
                        contentItem: TextInput {
                            text: amountSpin.textFromValue(amountSpin.value, amountSpin.locale)
                            color: "white"; font.pixelSize: 16; horizontalAlignment: Qt.AlignHCenter; verticalAlignment: Qt.AlignVCenter
                            readOnly: !amountSpin.editable; validator: amountSpin.validator; inputMethodHints: Qt.ImhDigitsOnly
                        }
                        // 내부 인디케이터 숨김 (외부 버튼 사용)
                        up.indicator: Item {}
                        down.indicator: Item {}
                    }

                    // [+] 버튼
                    Button {
                        text: "+"; width: 40; height: 40
                        background: Rectangle { color: "#444"; radius: 4 }
                        contentItem: Text { text: "+"; color: "white"; font.bold: true; font.pixelSize: 20; anchors.centerIn: parent }
                        onClicked: amountSpin.increase()
                    }

                    Item { Layout.fillWidth: true } // 여백

                    // 최대 버튼들
                    Button {
                        text: "매수 최대"
                        background: Rectangle { color: "#333"; border.color: window.colorUp; radius: 4 }
                        contentItem: Text { text: parent.text; color: window.colorUp }
                        onClicked: {
                            var maxBuy = Math.floor(window.cash / tradeModal.stockPrice);
                            amountSpin.value = (maxBuy > 0) ? maxBuy : 1;
                        }
                    }
                    Button {
                        text: "매도 최대"
                        background: Rectangle { color: "#333"; border.color: window.colorDown; radius: 4 }
                        contentItem: Text { text: parent.text; color: window.colorDown }
                        onClicked: {
                            var maxSell = tradeModal.stockOwned;
                            amountSpin.value = (maxSell > 0) ? maxSell : 1;
                        }
                    }
                }

                Text {
                    text: "총 거래 금액: " + (tradeModal.stockPrice * tradeModal.tradeAmount).toLocaleString(Qt.locale(), 'f', 0) + " 원"
                    color: (window.cash >= tradeModal.stockPrice * tradeModal.tradeAmount) ? "white" : "red"
                    font.bold: true; font.pixelSize: 16; Layout.alignment: Qt.AlignRight
                }

                // 매수/매도 버튼
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Button {
                        text: "매수"
                        Layout.fillWidth: true
                        enabled: (window.cash >= tradeModal.stockPrice * tradeModal.tradeAmount)
                        background: Rectangle {
                            color: parent.enabled ? window.colorUp : "#555"
                            radius: 4
                        }
                        contentItem: Text {
                            text: "매수"; color: parent.enabled ? "white" : "#aaa"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            backend.buyStock(tradeModal.stockIndex, tradeModal.tradeAmount);
                            tradeModal.close();
                        }
                    }
                    Button {
                        text: "매도"
                        Layout.fillWidth: true
                        enabled: (tradeModal.stockOwned >= tradeModal.tradeAmount)
                        background: Rectangle {
                            color: parent.enabled ? window.colorDown : "#555"
                            radius: 4
                        }
                        contentItem: Text {
                            text: "매도"; color: parent.enabled ? "white" : "#aaa"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            backend.sellStock(tradeModal.stockIndex, tradeModal.tradeAmount);
                            tradeModal.close();
                        }
                    }
                }
            }
        }
    }

    // --- 뉴스 디테일 팝업 ---
    Popup {
        id: newsDetailPopup
        anchors.centerIn: parent; width: 800; height: 600; modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property int viewingIndex: newsHistoryModel.count - 1
        onOpened: viewingIndex = newsHistoryModel.count - 1
        background: Rectangle { color: "#f4f1ea"; border.color: "#333"; border.width: 2 }
        contentItem: Item {
            anchors.fill: parent
            Button {
                text: "✕"; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                width: 40; height: 40; z: 10; background: Rectangle { color: "transparent" }
                contentItem: Text { text: "✕"; color: "#333"; font.pixelSize: 28; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: newsDetailPopup.close()
            }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 30; spacing: 20
                Text { text: "📰 THE DAILY MARKET ARCHIVE"; font.family: "Times New Roman"; font.bold: true; font.pixelSize: 32; color: "#111"; Layout.alignment: Qt.AlignHCenter }
                Rectangle {
                    Layout.fillWidth: true; height: 50; color: "transparent"
                    ListView {
                        anchors.fill: parent; orientation: ListView.Horizontal; spacing: 10; model: newsHistoryModel; clip: true
                        delegate: Button {
                            width: 80; height: 40; background: Rectangle { color: index === newsDetailPopup.viewingIndex ? "#111" : "#ddd"; radius: 5 }
                            contentItem: Text { text: model.dayIdx + "일차"; color: index === newsDetailPopup.viewingIndex ? "white" : "black"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: newsDetailPopup.viewingIndex = index
                        }
                    }
                }
                Rectangle { height: 2; color: "#333"; Layout.fillWidth: true }
                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    TextArea {
                        readOnly: true; textFormat: Text.RichText; color: "#111"; background: null; font.family: "Times New Roman"
                        // [수정] \n을 <br>로 치환하여 줄바꿈 적용
                        text: {
                            var item = newsHistoryModel.get(newsDetailPopup.viewingIndex);
                            return item ? "<h3>" + item.title + "</h3><br><p style='font-size:18px'>" + item.body.replace(/\n/g, "<br>") + "</p>" : ""
                        }
                    }
                }
            }
        }
    }

    // --- 정산 팝업 ---
    Popup {
        id: settlementPopup
        anchors.centerIn: parent; width: 500; height: 600; modal: true; focus: true
        closePolicy: Popup.NoAutoClose
        background: Rectangle { color: "#1e1e1e"; border.color: "#ff9800"; border.width: 2; radius: 10 }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 25; spacing: 15
            Text { text: "🌙 " + (window.day - 1) + "일차 정산 결과"; color: "white"; font.pixelSize: 24; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Rectangle { height: 1; color: "#555"; Layout.fillWidth: true }
            RowLayout {
                Layout.fillWidth: true; spacing: 20
                Column { Text { text: "이전 자산"; color: "#aaa"; font.pixelSize: 14 } Text { text: window.prevAsset.toLocaleString(Qt.locale(), 'f', 0); color: "white"; font.pixelSize: 18 } }
                Text { text: "▶"; color: "#ff9800"; font.pixelSize: 20 }
                Column {
                    Text { text: "현재 자산"; color: "#aaa"; font.pixelSize: 14 }
                    Text { text: window.totalAsset.toLocaleString(Qt.locale(), 'f', 0); color: window.totalAsset >= window.prevAsset ? window.colorUp : window.colorDown; font.pixelSize: 18; font.bold: true }
                }
            }
            Text { text: "상세 등락 내역"; color: "#aaa"; font.pixelSize: 14; Layout.topMargin: 10 }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: stockModel
                delegate: Item {
                    width: parent.width; height: 40
                    RowLayout {
                        anchors.fill: parent
                        Text { text: model.name; color: "white"; font.bold: true; Layout.preferredWidth: 100 }
                        Item { Layout.fillWidth: true }
                        Text { text: model.price.toLocaleString(Qt.locale(), 'f', 0) + "원"; color: "white" }
                        Text {
                            text: (model.changeRate > 0 ? "+" : "") + model.changeRate.toFixed(1) + "%"
                            color: model.changeRate > 0 ? window.colorUp : (model.changeRate < 0 ? window.colorDown : window.colorSame)
                            font.bold: true; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
            Button {
                text: "다음 날로 진행"; Layout.fillWidth: true; height: 50
                background: Rectangle { color: "#ff9800"; radius: 5 }
                contentItem: Text { text: "다음 날로 진행"; color: "white"; font.bold: true; anchors.centerIn: parent }
                onClicked: settlementPopup.close()
            }
        }
    }

    // --- 게임 오버 팝업 ---
    Popup {
        id: gameOverPopup
        anchors.centerIn: parent; width: 400; height: 300
        modal: true; focus: true
        closePolicy: Popup.NoAutoClose
        property bool isVictory: false
        property string messageText: ""
        background: Rectangle {
            color: "#1e1e1e"
            border.color: gameOverPopup.isVictory ? window.colorUp : window.colorDown
            border.width: 3; radius: 15
        }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 30; spacing: 20
            Text {
                text: gameOverPopup.isVictory ? "🎉 VICTORY! 🎉" : "💀 GAME OVER 💀"
                color: gameOverPopup.isVictory ? window.colorUp : window.colorDown
                font.pixelSize: 32; font.bold: true; Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: gameOverPopup.messageText
                color: "white"; font.pixelSize: 16; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true; Layout.fillHeight: true
            }
            Button {
                text: "게임 종료"
                Layout.fillWidth: true; height: 50
                background: Rectangle { color: "#444"; radius: 5 }
                contentItem: Text { text: "게임 종료"; color: "white"; font.bold: true; anchors.centerIn: parent }
                onClicked: Qt.quit()
            }
        }
    }

    // --- 알림 팝업 ---
    Popup {
        id: alertPopup
        anchors.centerIn: parent; width: 300; height: 150; modal: true
        property string message: ""
        background: Rectangle { color: "#333"; radius: 10; border.color: "#fff" }
        contentItem: ColumnLayout {
            Text { text: alertPopup.message; color: "white"; Layout.alignment: Qt.AlignCenter }
            Button { text: "확인"; Layout.alignment: Qt.AlignCenter; onClicked: alertPopup.close() }
        }
    }

    // --- 로딩 오버레이 ---
    Rectangle {
        id: loadingOverlay
        anchors.fill: parent; color: "#cc000000"; visible: false; z: 100
        MouseArea { anchors.fill: parent }
        Column {
            anchors.centerIn: parent; spacing: 20
            BusyIndicator { running: loadingOverlay.visible; width: 60; height: 60; palette.dark: window.colorUp }
            Text { text: "시장 데이터 정산 중..."; color: "white"; font.pixelSize: 20; font.bold: true }
        }
    }

    // --- 시뮬레이션 타이머 ---
    Timer {
        id: simulationTimer
        interval: 1000; repeat: false
        onTriggered: {
            loadingOverlay.visible = false
            backend.nextTurn()
            if (window.day <= window.maxDay) {
                settlementPopup.open()
            }
        }
    }
}
