import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 8000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        anchors.fill: parent
        Text {
            anchors.centerIn: parent
            text: "Welcome to LyargoOS"
            font.pixelSize: 36
            font.bold: true
            color: "#fcfcfc"
        }
    }

    Slide {
        anchors.fill: parent
        Text {
            anchors.centerIn: parent
            text: "Built on Void Linux"
            font.pixelSize: 36
            font.bold: true
            color: "#fcfcfc"
        }
    }

    Slide {
        anchors.fill: parent
        Text {
            anchors.centerIn: parent
            text: "Fast, secure, and customizable"
            font.pixelSize: 36
            font.bold: true
            color: "#fcfcfc"
        }
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }

    function onLeave() {
    }
}
