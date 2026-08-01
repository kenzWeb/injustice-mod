#import "IMRowBuilder.h"
#import "IMTheme.h"

@interface IMValueRow ()
@property (nonatomic, strong) UIView      *container;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UISlider    *slider;
@end

@implementation IMValueRow

- (void)setActive:(BOOL)active {
    self.container.alpha = active ? 1.0 : 0.35;
    self.container.userInteractionEnabled = active;
    if (!active) [self dismissKeyboard];
}

- (void)dismissKeyboard {
    [self.field resignFirstResponder];
}

@end

@interface IMRowBuilder ()
@property (nonatomic, weak) UIView *container;
@property (nonatomic, assign) CGFloat cursor;
@end

@implementation IMRowBuilder

- (instancetype)initWithContainer:(UIView *)container {
    if ((self = [super init])) {
        _container = container;
        _cursor = 0.0;
    }
    return self;
}

- (UIView *)pushRowOfHeight:(CGFloat)height {
    UIView *row = [[UIView alloc] initWithFrame:
        CGRectMake(0, self.cursor, IMPanelWidth, height)];
    [self.container addSubview:row];
    self.cursor += height;
    return row;
}

- (NSArray<UIButton *> *)addButtonTrioRow:(NSString *)title
                                   target:(id)target
                                   action:(SEL)action {
    UIView *row = [self pushRowOfHeight:46];
    [self titleLabelIn:row width:120 y:13].text = title;

    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    const CGFloat size = 34;
    const CGFloat gap = 8;
    CGFloat right = IMPanelWidth - IMPanelPadding;
    CGFloat x = right - size * 3 - gap * 2;

    for (NSInteger i = 0; i < 3; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(x + (size + gap) * i, 6, size, size);
        button.tag = i;
        [button setTitle:[NSString stringWithFormat:@"%ld", (long)(i + 1)]
                forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        button.layer.cornerRadius = 8;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:button];
        [buttons addObject:button];
    }

    [self addSeparator];
    return buttons;
}

- (UIView *)addCustomRowOfHeight:(CGFloat)height {
    return [self pushRowOfHeight:height];
}

- (void)addSeparator {
    UIView *line = [[UIView alloc] initWithFrame:
        CGRectMake(IMPanelPadding, self.cursor, IMPanelWidth - IMPanelPadding * 2, 0.5)];
    line.backgroundColor = IMColorHairline();
    [self.container addSubview:line];
    self.cursor += 0.5;
}

- (UILabel *)titleLabelIn:(UIView *)row width:(CGFloat)width y:(CGFloat)y {
    UILabel *label = [[UILabel alloc] initWithFrame:
        CGRectMake(IMPanelPadding, y, width, 20)];
    label.textColor = UIColor.whiteColor;
    label.font = IMFontRow();
    [row addSubview:label];
    return label;
}

- (UISwitch *)addSwitchRow:(NSString *)title
                    target:(id)target
                    action:(SEL)action
                    accent:(BOOL)accent {
    UIView *row = [self pushRowOfHeight:IMRowHeight];
    [self titleLabelIn:row width:190 y:11].text = title;

    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    toggle.transform = CGAffineTransformMakeScale(0.82, 0.82);
    toggle.center = CGPointMake(IMPanelWidth - IMPanelPadding - 21, IMRowHeight / 2);
    toggle.onTintColor = accent ? IMColorAccent() : IMColorPositive();
    [toggle addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    [row addSubview:toggle];

    [self addSeparator];
    return toggle;
}

- (IMValueRow *)addValueRow:(NSString *)title
                     target:(id)target
                fieldAction:(SEL)fieldAction
               sliderAction:(SEL)sliderAction
                      value:(double)value
                   maxValue:(double)maxValue
                   decimals:(BOOL)decimals {
    UIView *row = [self pushRowOfHeight:IMValueRowHeight];
    [self titleLabelIn:row width:140 y:11].text = title;

    IMValueRow *model = [IMValueRow new];
    model.container = row;

    UITextField *field = [[UITextField alloc] initWithFrame:
        CGRectMake(IMPanelWidth - IMPanelPadding - 116, 8, 116, 26)];
    field.text = decimals ? [NSString stringWithFormat:@"%.2f", value]
                          : [NSString stringWithFormat:@"%lld", (long long)value];
    field.textAlignment = NSTextAlignmentRight;
    field.textColor = IMColorAccent();
    field.font = IMFontValue();
    field.keyboardType = decimals ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumberPad;
    field.keyboardAppearance = UIKeyboardAppearanceDark;
    field.borderStyle = UITextBorderStyleNone;
    field.tintColor = IMColorAccent();
    field.adjustsFontSizeToFitWidth = YES;
    field.minimumFontSize = 10;
    if ([target conformsToProtocol:@protocol(UITextFieldDelegate)]) {
        field.delegate = (id<UITextFieldDelegate>)target;
    }
    [field addTarget:target action:fieldAction
        forControlEvents:UIControlEventEditingDidEnd];

    UIToolbar *accessory = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 220, 40)];
    accessory.barStyle = UIBarStyleBlack;
    accessory.items = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                      target:nil action:nil],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:model
                                                      action:@selector(dismissKeyboard)]
    ];
    [accessory sizeToFit];
    field.inputAccessoryView = accessory;
    [row addSubview:field];

    UISlider *slider = [[UISlider alloc] initWithFrame:
        CGRectMake(IMPanelPadding, 36, IMPanelWidth - IMPanelPadding * 2, 20)];
    slider.minimumValue = 0.0;
    slider.maximumValue = (float)maxValue;
    slider.value = (float)MIN(value, maxValue);
    slider.minimumTrackTintColor = IMColorAccent();
    slider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.16];
    [slider addTarget:target action:sliderAction
        forControlEvents:UIControlEventValueChanged];
    [row addSubview:slider];

    model.field = field;
    model.slider = slider;

    [self addSeparator];
    return model;
}

- (UIButton *)addButtonRow:(NSString *)title target:(id)target action:(SEL)action {
    UIView *row = [self pushRowOfHeight:IMButtonRowHeight];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(IMPanelPadding, 7,
                              IMPanelWidth - IMPanelPadding * 2, 30);
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    button.layer.cornerRadius = 9;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:button];

    [self addSeparator];
    return button;
}

- (UILabel *)addCaption:(NSString *)text {
    UIView *row = [self pushRowOfHeight:18];
    UILabel *label = [[UILabel alloc] initWithFrame:
        CGRectMake(IMPanelPadding, 1, IMPanelWidth - IMPanelPadding * 2, 14)];
    label.text = text;
    label.textColor = IMColorDim();
    label.font = IMFontCaption();
    [row addSubview:label];
    return label;
}

@end
