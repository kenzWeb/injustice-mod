#pragma once
#import <UIKit/UIKit.h>

@interface IMValueRow : NSObject
@property (nonatomic, strong, readonly) UIView      *container;
@property (nonatomic, strong, readonly) UITextField *field;
@property (nonatomic, strong, readonly) UISlider    *slider;
- (void)setActive:(BOOL)active;
- (void)dismissKeyboard;
@end

@interface IMRowBuilder : NSObject
@property (nonatomic, readonly) CGFloat cursor;
- (instancetype)initWithContainer:(UIView *)container;
- (UISwitch *)addSwitchRow:(NSString *)title
                    target:(id)target
                    action:(SEL)action
                    accent:(BOOL)accent;
- (IMValueRow *)addValueRow:(NSString *)title
                     target:(id)target
                fieldAction:(SEL)fieldAction
               sliderAction:(SEL)sliderAction
                      value:(double)value
                   maxValue:(double)maxValue
                   decimals:(BOOL)decimals;
- (UIButton *)addButtonRow:(NSString *)title target:(id)target action:(SEL)action;
- (UILabel *)addCaption:(NSString *)text;
- (NSArray<UIButton *> *)addButtonTrioRow:(NSString *)title
                                   target:(id)target
                                   action:(SEL)action;
- (UIView *)addCustomRowOfHeight:(CGFloat)height;
- (void)addSeparator;
@end
