import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Schedule.js" as Schedule

Panel {
  id: root
  moduleName: "dizziee.auto-wallpaper"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var intervalOptions: Schedule.intervalOptions()
  readonly property var modeOptions: Schedule.modeOptions()
  readonly property var scheduleTypeOptions: Schedule.scheduleTypeOptions()
  property bool scheduleEditorOpen: false
  property int editingScheduleIndex: -1
  property int draftHour: 8
  property int draftMinute: 0
  property string draftPeriod: "AM"
  property string draftWallpaper: ""
  property bool wallpaperPickerOpen: false
  readonly property var draftWallpaperEntry: root.wallpaperForPath(root.draftWallpaper)

  // Square wallpaper preview geometry. Cells are exactly cellSize x cellSize
  // with a wrapping grid driven by the content width.
  readonly property real cellSize: Style.space(72)
  readonly property real cellSpacing: Style.space(8)
  readonly property int gridColumns: Math.max(1, Math.floor(
    ((content ? content.width : 0) + root.cellSpacing) / (root.cellSize + root.cellSpacing)))
  readonly property int gridRows: Math.ceil(
    (root.service ? root.service.wallpaperList.length : 0) / root.gridColumns)
  readonly property real gridHeight: root.gridRows * root.cellSize
    + (root.gridRows > 1 ? (root.gridRows - 1) * root.cellSpacing : 0)

  function open() {
    if (service) {
      service.nowEpoch = new Date().getTime()
      // Only when opened: refresh current wallpaper + warm Omarchy thumbnails.
      service.updateCurrent()
      service.refreshCatalog(true)
    }
    controller.show()
  }

  function close() {
    root.wallpaperPickerOpen = false
    root.scheduleEditorOpen = false
    controller.hide()
  }
  function toggle() { opened ? close() : open() }

  function wallpaperForPath(path) {
    var list = root.service ? root.service.wallpaperList : []
    for (var i = 0; i < list.length; i++)
      if (list[i].path === path) return list[i]
    return { path: path || "", thumb: path || "", name: Schedule.wallpaperName(path) }
  }

  function loadDraftTime(minutes) {
    var value = Schedule.minute(minutes, 0)
    var hour24 = Math.floor(value / 60)
    var hour12 = hour24 % 12
    root.draftHour = hour12 === 0 ? 12 : hour12
    root.draftMinute = value % 60
    root.draftPeriod = hour24 >= 12 ? "PM" : "AM"
  }

  function draftTime() {
    return (root.draftHour % 12 + (root.draftPeriod === "PM" ? 12 : 0)) * 60
      + root.draftMinute
  }

  function beginAddSchedule() {
    var now = new Date()
    root.editingScheduleIndex = -1
    root.loadDraftTime(now.getHours() * 60 + now.getMinutes())
    root.draftWallpaper = ""
    root.scheduleEditorOpen = true
  }

  function beginEditSchedule(index) {
    if (!root.service || index < 0 || index >= root.service.dailyEntries.length) return
    var entry = root.service.dailyEntries[index]
    root.editingScheduleIndex = index
    root.loadDraftTime(entry.time)
    root.draftWallpaper = entry.wallpaper
    root.scheduleEditorOpen = true
  }

  function saveScheduleEditor() {
    if (!root.service) return
    if (root.service.saveDailyEntry(root.editingScheduleIndex, root.draftTime(),
                                    root.draftWallpaper)) {
      root.scheduleEditorOpen = false
      root.editingScheduleIndex = -1
    }
  }

  function chooseWallpaper(path) {
    root.draftWallpaper = path
    root.wallpaperPickerOpen = false
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.wallpaperPickerOpen) root.wallpaperPickerOpen = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if ((text === "a" || text === "A") && root.service) root.service.applyNow()
        else if ((text === "e" || text === "E") && root.service)
          root.service.setEnabled(!root.service.enabled)
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
          id: content
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            Layout.fillWidth: true
            title: "Auto Wallpaper"
            meta: !root.service ? "Service unavailable" : root.service.nextText()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰉊"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          PanelSectionHeader {
            Layout.fillWidth: true
            text: "WALLPAPERS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Text {
            Layout.fillWidth: true
            text: root.service ? root.service.statusText() : ""
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: root.gridHeight
            spacing: root.cellSpacing

            Repeater {
              model: root.service ? root.service.wallpaperList : []

              delegate: Rectangle {
                id: cell
                required property var modelData
                readonly property bool isCurrent: root.service
                  && root.service.currentWallpaper === modelData.path
                width: root.cellSize
                height: root.cellSize
                color: root.foreground
                clip: true

                Image {
                  anchors.fill: parent
                  // Only decode when the panel is open; use Omarchy's cached
                  // thumbnail + a small sourceSize so the decode is tiny.
                  // cache:false so the decoded pixmap is dropped on close
                  // (re-decode on reopen is trivial for 240px thumbnails).
                  source: root.opened ? Util.fileUrl(modelData.thumb) : ""
                  sourceSize: Qt.size(240, 240)
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                  smooth: true
                }

                // Dim the non-current cells for contrast.
                Rectangle {
                  anchors.fill: parent
                  color: Util.alpha(root.foreground, cell.isCurrent ? 0 : 0.22)
                }

                // Current border drawn ON TOP so the image can't hide it.
                Rectangle {
                  anchors.fill: parent
                  color: "transparent"
                  border.color: cell.isCurrent ? root.foreground : root.dim
                  border.width: cell.isCurrent ? 2 : 1
                }

                ToolTip.visible: cellMouse.containsMouse
                ToolTip.text: modelData.name
                ToolTip.delay: 500

                MouseArea {
                  id: cellMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.service) root.service.setWallpaper(modelData.path)
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: "Click a wallpaper to set it now. The current one is highlighted with a border."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          PanelSectionHeader {
            Layout.fillWidth: true
            text: "SCHEDULE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Dropdown {
            Layout.fillWidth: true
            label: "Schedule"
            value: root.service ? root.service.scheduleType : Schedule.SCHEDULE_INTERVAL
            options: root.scheduleTypeOptions
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) {
              root.scheduleEditorOpen = false
              root.wallpaperPickerOpen = false
              if (root.service) root.service.updateSchedule({ scheduleType: value })
            }
          }

          Toggle {
            Layout.fillWidth: true
            label: "Automatic switching"
            description: root.service
              && root.service.scheduleType === Schedule.SCHEDULE_DAILY
                ? "Uses the selected wallpaper at each scheduled daily time."
                : "Cycles the active theme's wallpapers on an interval."
            checked: root.service ? root.service.enabled : false
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            enabled: root.service !== null
            onClicked: if (root.service) root.service.setEnabled(!root.service.enabled)
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            visible: !root.service
              || root.service.scheduleType === Schedule.SCHEDULE_INTERVAL

            Dropdown {
              Layout.fillWidth: true
              label: "Interval"
              value: root.service ? String(root.service.intervalMinutes) : "30"
              options: root.intervalOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) {
                if (root.service) root.service.updateSchedule({ intervalMinutes: Number(value) })
              }
            }

            Dropdown {
              Layout.fillWidth: true
              label: "Order"
              value: root.service ? root.service.mode : "sequential"
              options: root.modeOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) {
                if (root.service) root.service.updateSchedule({ mode: value })
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            visible: root.service
              && root.service.scheduleType === Schedule.SCHEDULE_DAILY

            Text {
              Layout.fillWidth: true
              visible: root.service && root.service.dailyEntries.length === 0
              text: "No daily times yet. Add one for each wallpaper change."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.service ? root.service.dailyEntries : []

              delegate: Rectangle {
                id: scheduleRow
                required property int index
                required property var modelData
                readonly property var wallpaper: root.wallpaperForPath(modelData.wallpaper)
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(64)
                color: Util.alpha(root.foreground, 0.07)
                border.color: Util.alpha(root.foreground, 0.18)
                border.width: 1
                radius: Style.space(4)

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(8)

                  Rectangle {
                    Layout.preferredWidth: Style.space(72)
                    Layout.fillHeight: true
                    color: root.foreground
                    clip: true

                    Image {
                      anchors.fill: parent
                      source: root.opened && scheduleRow.wallpaper.thumb
                        ? Util.fileUrl(scheduleRow.wallpaper.thumb) : ""
                      sourceSize: Qt.size(240, 160)
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      cache: false
                    }
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                      Layout.fillWidth: true
                      text: Schedule.clockLabel(scheduleRow.modelData.time)
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      Layout.fillWidth: true
                      text: scheduleRow.wallpaper.name
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Button {
                    text: "Edit"
                    bordered: true
                    focusable: true
                    foreground: root.foreground
                    accent: Color.accent
                    fontFamily: root.fontFamily
                    enabled: !root.scheduleEditorOpen
                    onClicked: root.beginEditSchedule(scheduleRow.index)
                  }

                  Button {
                    text: "Remove"
                    bordered: true
                    focusable: true
                    foreground: root.urgent
                    accent: root.urgent
                    fontFamily: root.fontFamily
                    enabled: !root.scheduleEditorOpen
                    onClicked: {
                      if (root.service) root.service.removeDailyEntry(scheduleRow.index)
                      if (root.editingScheduleIndex === scheduleRow.index)
                        root.scheduleEditorOpen = false
                    }
                  }
                }
              }
            }

            Button {
              Layout.fillWidth: true
              visible: !root.scheduleEditorOpen
              text: "Add schedule time"
              iconText: "+"
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.beginAddSchedule()
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: editorContent.implicitHeight + Style.space(16)
              visible: root.scheduleEditorOpen
              color: Util.alpha(root.foreground, 0.07)
              border.color: Util.alpha(root.foreground, 0.22)
              border.width: 1
              radius: Style.space(4)

              ColumnLayout {
                id: editorContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                spacing: Style.space(8)

                Text {
                  Layout.fillWidth: true
                  text: root.editingScheduleIndex >= 0 ? "Edit schedule time" : "Add schedule time"
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(6)

                  NumberField {
                    label: "Hour"
                    value: root.draftHour
                    from: 1
                    to: 12
                    fieldWidth: Style.space(82)
                    foreground: root.foreground
                    accent: Color.accent
                    fontFamily: root.fontFamily
                    onModified: function(value) { root.draftHour = value }
                  }

                  NumberField {
                    label: "Minute"
                    value: root.draftMinute
                    from: 0
                    to: 59
                    fieldWidth: Style.space(82)
                    foreground: root.foreground
                    accent: Color.accent
                    fontFamily: root.fontFamily
                    onModified: function(value) { root.draftMinute = value }
                  }

                  ColumnLayout {
                    spacing: Style.spacing.md

                    Text {
                      text: "Period"
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Button {
                      text: root.draftPeriod
                      bordered: true
                      focusable: true
                      foreground: root.foreground
                      accent: Color.accent
                      fontFamily: root.fontFamily
                      onClicked: root.draftPeriod = root.draftPeriod === "AM" ? "PM" : "AM"
                    }
                  }

                  Item { Layout.fillWidth: true }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Rectangle {
                    Layout.preferredWidth: Style.space(88)
                    Layout.preferredHeight: Style.space(56)
                    color: root.foreground
                    border.color: root.draftWallpaper ? Color.accent : root.dim
                    border.width: root.draftWallpaper ? 2 : 1
                    clip: true

                    Image {
                      anchors.fill: parent
                      source: root.opened && root.draftWallpaperEntry.thumb
                        ? Util.fileUrl(root.draftWallpaperEntry.thumb) : ""
                      sourceSize: Qt.size(240, 160)
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      cache: false
                    }

                    Text {
                      anchors.centerIn: parent
                      visible: !root.draftWallpaper
                      text: "No image"
                      textFormat: Text.PlainText
                      color: Color.background
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(3)

                    Text {
                      Layout.fillWidth: true
                      text: root.draftWallpaper
                        ? root.draftWallpaperEntry.name : "Choose a wallpaper"
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }

                    Button {
                      Layout.fillWidth: true
                      text: root.draftWallpaper ? "Change wallpaper" : "Choose wallpaper"
                      bordered: true
                      focusable: true
                      foreground: root.foreground
                      accent: Color.accent
                      fontFamily: root.fontFamily
                      onClicked: root.wallpaperPickerOpen = true
                    }
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Button {
                    Layout.fillWidth: true
                    text: "Cancel"
                    bordered: true
                    focusable: true
                    foreground: root.foreground
                    accent: Color.accent
                    fontFamily: root.fontFamily
                    onClicked: {
                      root.scheduleEditorOpen = false
                      root.editingScheduleIndex = -1
                    }
                  }

                  Button {
                    Layout.fillWidth: true
                    text: "Save time"
                    bordered: true
                    focusable: true
                    enabled: root.draftWallpaper !== ""
                    foreground: root.foreground
                    accent: Color.accent
                    fontFamily: root.fontFamily
                    onClicked: root.saveScheduleEditor()
                  }
                }
              }
            }
          }

          Button {
            Layout.fillWidth: true
            text: root.service && root.service.busy ? "Applying…"
              : (root.service && root.service.scheduleType === Schedule.SCHEDULE_DAILY
                  ? "Apply scheduled wallpaper now" : "Apply next wallpaper now")
            iconText: "󰑐"
            bordered: true
            focusable: true
            enabled: root.service && !root.service.busy
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.applyNow()
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          Text {
            Layout.fillWidth: true
            visible: root.service && (root.service.lastError !== "" || root.service.lastAction !== "")
            text: root.service && root.service.lastError !== ""
              ? root.service.lastError : (root.service ? root.service.lastAction : "")
            textFormat: Text.PlainText
            color: root.service && root.service.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            Layout.fillWidth: true
            text: root.service && root.service.scheduleType === Schedule.SCHEDULE_DAILY
              ? "Manual choices remain active until the next scheduled time."
              : "Manual choices and scheduled changes share the same rotation. "
                + (root.service && root.service.shuffle
                    ? "Shuffle plays every wallpaper once before repeating."
                    : "Sequential order advances by one wallpaper each interval.")
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      Rectangle {
        id: wallpaperPicker
        anchors.fill: parent
        z: 100
        visible: root.wallpaperPickerOpen
        color: Util.alpha(Color.background, 0.98)

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true

            Text {
              Layout.fillWidth: true
              text: "Choose wallpaper"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            Button {
              text: "Close"
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.wallpaperPickerOpen = false
            }
          }

          GridView {
            id: wallpaperGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.service ? root.service.wallpaperList : []
            cellWidth: root.cellSize + root.cellSpacing
            cellHeight: root.cellSize + root.cellSpacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
              id: pickerCell
              required property var modelData
              width: wallpaperGrid.cellWidth
              height: wallpaperGrid.cellHeight

              Rectangle {
                width: root.cellSize
                height: root.cellSize
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.foreground
                border.color: root.draftWallpaper === pickerCell.modelData.path
                  ? Color.accent : root.dim
                border.width: root.draftWallpaper === pickerCell.modelData.path ? 3 : 1
                clip: true

                Image {
                  anchors.fill: parent
                  anchors.margins: parent.border.width
                  source: root.opened ? Util.fileUrl(pickerCell.modelData.thumb) : ""
                  sourceSize: Qt.size(240, 240)
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                  smooth: true
                }

                ToolTip.visible: pickerMouse.containsMouse
                ToolTip.text: pickerCell.modelData.name
                ToolTip.delay: 400

                MouseArea {
                  id: pickerMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.chooseWallpaper(pickerCell.modelData.path)
                }
              }
            }
          }
        }
      }
    }
  }
}
