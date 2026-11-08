QT += core gui quick quickcontrols2 testlib
CONFIG += c++17 testcase
TARGET = harbor_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += ../src/backend.h ../src/selfusage.h ../src/theme.h ../src/translator.h
SOURCES += harbor_tests.cpp ../src/backend.cpp ../src/selfusage.cpp ../src/theme.cpp ../src/translator.cpp
