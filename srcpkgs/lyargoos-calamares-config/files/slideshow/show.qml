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
        Image {
            source: "slide-01.jpg"
            width: parent.width; height: parent.height
            fillMode: Image.Stretch
            anchors.centerIn: parent
        }
    }

    Slide {
        anchors.fill: parent
        Image {
            source: "slide-02.jpg"
            width: parent.width; height: parent.height
            fillMode: Image.Stretch
            anchors.centerIn: parent
        }
    }

    Slide {
        anchors.fill: parent
        Image {
            source: "slide-03.jpg"
            width: parent.width; height: parent.height
            fillMode: Image.Stretch
            anchors.centerIn: parent
        }
    }

    Slide {
        anchors.fill: parent
        Image {
            source: "slide-04.jpg"
            width: parent.width; height: parent.height
            fillMode: Image.Stretch
            anchors.centerIn: parent
        }
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }

    function onLeave() {
    }
}
