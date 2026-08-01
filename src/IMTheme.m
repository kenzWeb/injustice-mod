#import "IMTheme.h"

const CGFloat IMPanelWidth      = 292.0;
const CGFloat IMPanelPadding    = 16.0;
const CGFloat IMHeaderHeight    = 44.0;
const CGFloat IMRowHeight       = 42.0;
const CGFloat IMValueRowHeight  = 66.0;
const CGFloat IMButtonRowHeight = 44.0;

UIColor *IMColorAccent(void) {
    return [UIColor colorWithRed:1.00 green:0.27 blue:0.23 alpha:1.0];
}

UIColor *IMColorPositive(void) {
    return [UIColor colorWithRed:0.30 green:0.78 blue:0.42 alpha:1.0];
}

UIColor *IMColorReadout(void) {
    return [UIColor colorWithRed:0.42 green:0.98 blue:0.55 alpha:1.0];
}

UIColor *IMColorDim(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.45];
}

UIColor *IMColorHairline(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.10];
}

UIFont *IMFontRow(void) {
    return [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
}

UIFont *IMFontValue(void) {
    return [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
}

UIFont *IMFontCaption(void) {
    return [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
}

UIFont *IMFontReadout(void) {
    return [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
}
