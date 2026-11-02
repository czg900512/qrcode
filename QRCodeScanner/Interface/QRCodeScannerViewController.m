//
//  QRCodeScannerViewController.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRCodeScannerViewController.h"
#import "QRCodePickerView.h"
#import "QRScannerOrientation.h"
#import "QRScannerPreviewGeometry.h"
#import "QRCodeLocator.h"
#import "QRScannerState.h"
#import "QRScannerTorchButton.h"
#import "QRScannerTimer.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <Photos/Photos.h>

/// 扫描动画时长
const static CGFloat AnimationTime = 2.5f;
/// 打开扫描时的默认放大倍数，按普通广角镜头计算，并限制在这台手机允许的范围内
const static CGFloat kQRScannerDefaultZoomFactor = 1.3f;
/// 判断光线暗不暗用的感光度门槛
const static float kQRScannerLowLightISOThreshold = 800.f;
/// 判断光线暗不暗用的曝光时间门槛，单位是秒
const static NSTimeInterval kQRScannerLowLightExposureThreshold = 1.0 / 30.0;
/// 隔多久看一次光线暗不暗
const static NSTimeInterval kQRScannerLowLightSampleInterval = 0.5;
/// 连续几次都觉得暗，才显示手电筒
const static NSInteger kQRScannerLowLightShowCount = 2;
/// 手电筒关着时，连续几次都觉得亮，才把按钮藏起来
const static NSInteger kQRScannerLowLightHideCount = 3;
/// 自动拉近时，希望二维码在画面上不要超过这么宽
const static CGFloat kQRScannerAutoZoomMaxCodeWidth = 60.f;
/// 自动拉近最多放到普通广角的多少倍。多摄手机要再换算成系统实际使用的倍数
const static CGFloat kQRScannerMaxAutoZoomFactor = 5.f;
/// 拉近速度。太快时画面会突然跳一下
const static float kQRScannerZoomRampRate = 6.0f;
/// 还没看到码框时，找码最快大约每秒 30 次，实际还会受单帧耗时影响
const static NSTimeInterval kQRScannerVisionMinInterval = 0.03;
/// 已经看到码框后，找位置降到大约每秒 5 次，读内容交给系统扫码结果
const static NSTimeInterval kQRScannerVisionAfterBoxInterval = 0.20;
/// 对焦时画面会糊，但不完全停止找码，大约每秒再找 5 次远处的码
const static NSTimeInterval kQRScannerVisionDuringFocusInterval = 0.20;
/// 系统刚刚读出内容时，先不再用 Vision 找位置，Vision 只在系统还没读出来时帮忙找框
const static NSTimeInterval kQRScannerMetadataFreshInterval = 0.15;
/// 画面上有多个框、但暂时只读出一个码时，稍微等一下第二个；只有一个框就不用等
const static NSTimeInterval kQRScannerMultiCodeWaitInterval = 0.18;
/// 拉近之后如果刚才看到过多个框，再多等一会儿，给第二个码留出识别时间
const static NSTimeInterval kQRScannerMultiCodeAfterZoomWaitInterval = 0.28;
/// 自动拉近后，码距离屏幕四边至少留出的空白
const static CGFloat kQRScannerZoomKeepOnScreenInset = 20.f;
/// 刚请求拉近时，系统可能还没把“正在拉近”标记打开，这段时间内不要误判成已经拉完
const static NSTimeInterval kQRScannerZoomRampStartTimeout = 0.40;
/// 拉近结束后稍等一下再重新对焦，给镜头切换留出稳定时间
const static NSTimeInterval kQRScannerFocusAfterRampDelay = 0.08;
/// 处理完一个码之后稍等再开扫，避免马上又扫到同一个码
const static NSTimeInterval kQRScannerRestartAfterResolveDelay = 1.5;
/// 关掉多码选择后马上恢复相机，但短时间内不把刚才那一批码再弹出来
const static NSTimeInterval kQRScannerIgnoreAfterSelectorClose = 0.4;
/// 两次自动拉近的最短间隔，避免镜头刚切换完又立刻拉近
const static NSTimeInterval kQRScannerAutoZoomMinInterval = 0.5;
/// 拉近结束后要连续几次都确认镜头不再变焦，避免双摄切换时状态闪一下被当成已经结束
const static NSUInteger kQRScannerZoomRampSettledPolls = 3;
/// 拉近结束后，最多再等一会儿，让系统用新倍率刷新码的位置
const static NSTimeInterval kQRScannerPostZoomMetadataWait = 0.28;
/// 拉近后码的位置还没刷新时，过一小会儿再试着提交结果
const static NSTimeInterval kQRScannerPostZoomMetadataRetryInterval = 0.08;

@interface QRCodeScannerViewController () <AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, QRCodePickerViewDelegate>

/** 盖在预览上面的按钮和提示 */
@property (nonatomic, strong) UIView *containerView;

/** 扫码页返回按钮 */
@property (nonatomic, strong) UIButton *backButton;

/** 摄像头采集会话 */
@property (nonatomic, strong) AVCaptureSession *captureSession;

/** 当前后置采集设备 */
@property (nonatomic, strong) AVCaptureDevice *captureDevice;

/** 摄像头预览层 */
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;

/** 系统条码解码输出 */
@property (nonatomic, strong) AVCaptureMetadataOutput *captureMetadataOutput;

/** 交给找码逻辑的完整画面，不改变用户看到的预览 */
@property (nonatomic, strong) AVCaptureVideoDataOutput *captureVideoDataOutput;

/** 按帧轮流在画面各区域找二维码位置的入口 */
@property (nonatomic, strong) QRCodeLocator *codeLocator;

/** Vision 检测串行队列，避免堵住 sessionQueue */
@property (nonatomic, strong) dispatch_queue_t visionQueue;

/** Main、Vision、Session 队列共享的线程安全状态 */
@property (nonatomic, strong) QRScannerState *runtimeState;

/** 当前界面方向对应的相机方向，只在主线程更新 */
@property (nonatomic, assign) AVCaptureVideoOrientation currentVideoOrientation;

/** 主线程记下的预览坐标，找码线程只读 */
@property (atomic, strong) QRScannerPreviewGeometry *previewGeometry;

/** 只用来放扫描动画，不限制实际识别范围 */
@property (nonatomic, strong) UIView *scanPane;

/** 相册识别加载指示器 */
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicatorView;

/** 扫描动画线 */
@property (nonatomic, strong) UIImageView *scanLine;

/** 扫码提示图片 */
@property (nonatomic, strong) UIImageView *hintImageView;

/** 相册入口按钮 */
@property (nonatomic, strong) UIButton *albumButton;

/** 弱光时展示的手电筒控件 */
@property (nonatomic, strong) QRScannerTorchButton *torchControl;

/** AVCaptureSession 与设备配置专用串行队列 */
@property (nonatomic, strong) dispatch_queue_t sessionQueue;

/** 弱光检测定时器 */
@property (nonatomic, strong) QRScannerTimer *lowLightTimer;

/** 手电筒是否开启，仅在主线程读写 */
@property (nonatomic, assign) BOOL isTorchOn;

/** 当前设备是否支持手电筒 */
@property (nonatomic, assign) BOOL torchSupported;

/** 连续暗光采样计数 */
@property (nonatomic, assign) NSInteger darkSampleCount;

/** 连续亮光采样计数 */
@property (nonatomic, assign) NSInteger brightSampleCount;

/** 是否已经把系统识别范围设成整幅画面，避免每次布局都重复设置 */
@property (nonatomic, assign) BOOL didApplyFullMetadataROI;

/** 相机是否已经配置好。没权限或没有相机时保持为否 */
@property (nonatomic, assign) BOOL sessionConfigured;

/** 页面还没显示出来时先记下提示，显示后再弹窗 */
@property (nonatomic, copy, nullable) NSString *pendingAlertMessage;

/** 相机权限被拒绝时，等页面显示出来再提示去设置 */
@property (nonatomic, assign) BOOL needsCameraDeniedAlert;

/** 这一轮最多同时看到过几个码，拉近后用它决定要不要等第二个码 */
@property (nonatomic, assign) NSUInteger pendingVisibleBoxCount;

/** 当前要对焦的区域。一个码就对这个码，多个码就对它们围起来的区域 */
@property (nonatomic, assign) CGRect lastQRRectInPreview;

/** 短时间里已经读出内容的码 */
@property (nonatomic, strong) NSMutableArray<AVMetadataMachineReadableCodeObject *> *pendingDecodedObjects;

/** 等待第二个码的计时器 */
@property (nonatomic, strong) QRScannerTimer *multiCodeTimer;

/** 多个码的选择层。用弱引用，避免和页面互相抓住不放 */
@property (nonatomic, weak) QRCodePickerView *codePickerView;

/** 弹出选择层之前保持当前放大倍数，避免画面缩回去之后箭头对不准 */
@property (nonatomic, assign) BOOL preservePreviewZoomForPicker;

/** 在这个时间之前不提交扫码结果，避免刚关掉选择层又马上弹出来 */
@property (nonatomic, assign) NSTimeInterval ignoreDecodedCommitUntil;

/** 上一次自动拉近结束的时间，用来控制两次拉近的间隔，也用来等新的码位置 */
@property (nonatomic, assign) NSTimeInterval lastAutoZoomFinishedAt;

@end

@implementation QRCodeScannerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForegroundNotification) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackgroundNotification) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(captureDeviceSubjectAreaDidChange:)
                                                 name:AVCaptureDeviceSubjectAreaDidChangeNotification
                                               object:nil];
    self.currentVideoOrientation = AVCaptureVideoOrientationPortrait;
    
    self.view.backgroundColor = [UIColor blackColor];
    
    [self setupChildViews];
    [self layoutChildViews];
    [self requestCameraPermissionThenStart];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self updateCaptureOrientation];
    [self showPendingAlertIfNeeded];
    [self startScan];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (self.isMovingFromParentViewController || self.isBeingDismissed) {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
    // 离开页面时允许把倍率打回默认，后续若还有选择器回调则不再展示
    self.preservePreviewZoomForPicker = NO;
    [self stopScan];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    if (self.codePickerView) {
        [self.codePickerView dismiss];
    }
    // 旋转开始即丢掉旧方向上的待提交码和 Vision 帧，避免动画期间带上旧码
    [self.runtimeState invalidateCaptureGeneration];
    [self.runtimeState invalidateAutoZoom];
    [self resetQRCodeLocator];
    [self invalidatePendingScanResultsForGeometryChange];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
        self.captureVideoPreviewLayer.frame = self.view.layer.bounds;
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
        [self updateCaptureOrientation];
        [self invalidatePendingScanResultsForGeometryChange];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    self.captureVideoPreviewLayer.frame = self.view.layer.bounds;
    [self refreshPreviewGeometry];
    // 仅当扫框几何变化时更新；实际 setRectOfInterest 在 sessionQueue，避免主线程堵死
    [self updateRectOfInterest];
}

- (void)setupChildViews {
    [self.containerView addSubview:self.backButton];
    [self.containerView addSubview:self.scanPane];
    [self.containerView addSubview:self.hintImageView];
    [self.containerView addSubview:self.torchControl];
    [self.containerView addSubview:self.albumButton];
    [self.containerView addSubview:self.loadingIndicatorView];
    
    [self.view.layer addSublayer:self.captureVideoPreviewLayer];
    [self.view addSubview:self.containerView];
}

- (void)layoutChildViews {
    NSArray<UIView *> *layoutViews = @[self.containerView,
                                       self.backButton,
                                       self.scanPane,
                                       self.hintImageView,
                                       self.albumButton,
                                       self.torchControl,
                                       self.loadingIndicatorView];
    for (UIView *layoutView in layoutViews) {
        layoutView.translatesAutoresizingMaskIntoConstraints = NO;
    }
    // 扫描线用 frame 做位移动画，不能被自动布局约束拉回去
    self.scanLine.translatesAutoresizingMaskIntoConstraints = YES;
    CGFloat bottomGap = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? 60.f : 30.f;
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.containerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.containerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.containerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.containerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.backButton.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:8.f],
        [self.backButton.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:12.f],
        [self.backButton.widthAnchor constraintEqualToConstant:44.f],
        [self.backButton.heightAnchor constraintEqualToConstant:44.f],

        [self.albumButton.centerXAnchor constraintEqualToAnchor:self.containerView.centerXAnchor],
        [self.albumButton.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-bottomGap],
        [self.albumButton.widthAnchor constraintEqualToConstant:40.f],
        [self.albumButton.heightAnchor constraintEqualToConstant:70.f],

        [self.hintImageView.centerXAnchor constraintEqualToAnchor:self.containerView.centerXAnchor],
        [self.hintImageView.bottomAnchor constraintEqualToAnchor:self.albumButton.topAnchor constant:-25.f],
        [self.hintImageView.widthAnchor constraintEqualToConstant:217.f],
        [self.hintImageView.heightAnchor constraintEqualToConstant:22.f],

        [self.torchControl.centerXAnchor constraintEqualToAnchor:self.containerView.centerXAnchor],
        [self.torchControl.bottomAnchor constraintEqualToAnchor:self.hintImageView.topAnchor constant:-20.f],
        [self.torchControl.widthAnchor constraintEqualToConstant:80.f],
        [self.torchControl.heightAnchor constraintEqualToConstant:65.f],

        [self.scanPane.topAnchor constraintEqualToAnchor:self.backButton.bottomAnchor constant:20.f],
        [self.scanPane.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:40.f],
        [self.scanPane.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-40.f],
        [self.scanPane.bottomAnchor constraintEqualToAnchor:self.hintImageView.topAnchor constant:-40.f],

        [self.loadingIndicatorView.centerXAnchor constraintEqualToAnchor:self.containerView.centerXAnchor],
        [self.loadingIndicatorView.centerYAnchor constraintEqualToAnchor:self.containerView.centerYAnchor],
    ]];
}

/** 启动扫描 */
- (void)launchScan {
    AVCaptureDevice *device = [self getBestCameraDevice];
    if (!device) {
        [self showAlertMessage:@"当前设备没有可用的相机"];
        return;
    }
    self.captureDevice = device;
    self.torchSupported = device.hasTorch;
    [self configureCaptureDevice:device];
    
    NSError *inputError = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&inputError];
    if (!input || ![self.captureSession canAddInput:input]) {
        [self showAlertMessage:@"无法打开相机"];
        return;
    }
    [self.captureSession addInput:input];
    if ([self.captureSession canAddOutput:self.captureMetadataOutput]) {
        [self.captureSession addOutput:self.captureMetadataOutput];
    }
    if ([self.captureSession canAddOutput:self.captureVideoDataOutput]) {
        [self.captureSession addOutput:self.captureVideoDataOutput];
    }
    [self updateCaptureOrientation];
    
    NSArray *desiredTypes = @[AVMetadataObjectTypeQRCode,
                              AVMetadataObjectTypeCode39Code,
                              AVMetadataObjectTypeCode128Code,
                              AVMetadataObjectTypeCode39Mod43Code,
                              AVMetadataObjectTypeEAN13Code,
                              AVMetadataObjectTypeEAN8Code,
                              AVMetadataObjectTypeCode93Code];
    
    NSMutableArray *availableTypes = [NSMutableArray array];
    for (NSString *type in desiredTypes) {
        // 检查每个 desiredTypes 中的类型是否存在于设备支持的类型数组中
        if ([self.captureMetadataOutput.availableMetadataObjectTypes containsObject:type]) {
            [availableTypes addObject:type];
        }
    }
    
    if (availableTypes.count == 0) {
        [self showAlertMessage:@"无法获取支持的类型"];
        return;
    }
    [self.captureMetadataOutput setMetadataObjectTypes:availableTypes];
    self.sessionConfigured = YES;
    
    [self.loadingIndicatorView startAnimating];
    [self.runtimeState beginScanning];
    [self resetQRCodeLocator];
    self.captureVideoPreviewLayer.frame = self.view.layer.bounds;
    [self.view layoutIfNeeded];
    [self refreshPreviewGeometry];
    [self updateRectOfInterest];
    CGPoint defaultFocusDevicePoint = [self currentFocusDevicePoint];
    dispatch_async(self.sessionQueue, ^{
        [self.captureSession startRunning];
        // zoom 必须在 startRunning 之后再设：session 激活 format 时会把启动前写入的 videoZoomFactor 打回默认
        [self resetZoomAndFocusToDefaultLockedWithDevicePoint:defaultFocusDevicePoint];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicatorView stopAnimating];
            
            [self.scanPane layoutIfNeeded];
            [self.view layoutIfNeeded];
            [self refreshPreviewGeometry];
            [self updateRectOfInterest];

            [UIView animateWithDuration:.25f animations:^{
                self.hintImageView.alpha = 1.f;
            } completion:^(BOOL finished) {
                self.scanLine.frame = CGRectMake(0.f, -40.f, CGRectGetWidth(self.scanPane.bounds), 81.f);
                [self.scanLine.layer addAnimation:[self moveAnimation] forKey:nil];
            }];
            [self startLowLightMonitoring];
        });
    });
}

/// 在 Vision 串行队列清理上次会话状态，确保重启后从全画面阶段开始搜索
- (void)resetQRCodeLocator {
    dispatch_async(self.visionQueue, ^{
        [self.codeLocator reset];
    });
}

/**
 让系统在整幅预览里识别，不裁成一小块。

 @note 识别范围必须在相机会话那条队列上改。在主线程同步改，容易和相机互相等待，把页面卡死。
 @note 系统识别和找码都看整幅预览。扫描框只是界面动画，不限制识别范围。
 */
- (void)updateRectOfInterest {
    if (!self.captureMetadataOutput) {
        return;
    }
    if (self.didApplyFullMetadataROI) {
        return;
    }
    self.didApplyFullMetadataROI = YES;
    
    AVCaptureMetadataOutput *output = self.captureMetadataOutput;
    dispatch_async(self.sessionQueue, ^{
        output.rectOfInterest = CGRectMake(0.f, 0.f, 1.f, 1.f);
    });
}

/** 开始扫描动画 */
- (void)startScanAnimation {
    [self.scanLine.layer addAnimation:[self moveAnimation] forKey:nil];
    self.scanLine.hidden = NO;
}

/** 停止扫描动画 */
- (void)stopScanAnimation {
    [self.scanLine.layer removeAllAnimations];
    self.scanLine.hidden = YES;
}

/** 从停止状态重新开始扫描。页面仍在窗口上时有效 */
- (void)resumeScanning {
    [self.runtimeState setResolving:NO];
    [self startScan];
}

/** 开始扫描 */
- (void)startScan {
    QRScannerStateSnapshot *snapshot = [self.runtimeState snapshot];
    if (!self.sessionConfigured || !self.view.window || self.presentedViewController || snapshot.isScanning || snapshot.isResolving) {
        // 如果不在当前页面, 或者正在扫描或者正在处理, 则返回
        return;
    }

    self.preservePreviewZoomForPicker = NO;
    self.lastAutoZoomFinishedAt = 0;
    
    // 标记为 正在扫描
    [self.runtimeState beginScanning];
    [self resetQRCodeLocator];

    self.lastQRRectInPreview = CGRectZero;
    [self clearPendingDecodedCodes];
    
    // 开始扫描动画
    [self startScanAnimation];
    CGPoint defaultFocusDevicePoint = [self currentFocusDevicePoint];
    dispatch_async(self.sessionQueue, ^{
        [self.captureSession startRunning];
        [self resetZoomAndFocusToDefaultLockedWithDevicePoint:defaultFocusDevicePoint];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startLowLightMonitoring];
        });
    });
}

/** 停止扫描 */
- (void)stopScan {
    [self stopScanResettingPreviewZoom:YES completion:nil];
}

/**
 停采集。

 @param resetPreviewZoom YES 时先把倍率打回默认再 stopRunning；NO 时只取消正在进行的拉近，保持当前倍率，好让多个码的箭头对准停住的画面。
 @param completion stopRunning 完成后回到主线程；可为 nil。
 */
- (void)stopScanResettingPreviewZoom:(BOOL)resetPreviewZoom
                             completion:(void (^)(void))completion {
    [self.runtimeState stopScanning];
    [self stopScanAnimation];
    [self stopLowLightMonitoring];
    [self setTorchOn:NO];
    [self setTorchButtonVisible:NO animated:NO];

    self.lastQRRectInPreview = CGRectZero;
    [self clearPendingDecodedCodes];

    if (!resetPreviewZoom) {
        self.preservePreviewZoomForPicker = YES;
    }

    BOOL shouldResetZoom = resetPreviewZoom && !self.preservePreviewZoomForPicker;
    CGPoint defaultFocusDevicePoint = [self currentFocusDevicePoint];
    dispatch_async(self.sessionQueue, ^{
        if (shouldResetZoom) {
            [self resetZoomAndFocusToDefaultLockedWithDevicePoint:defaultFocusDevicePoint];
        } else {
            [self cancelZoomRampKeepingCurrentFactor];
        }
        if (self.captureSession.isRunning) {
            [self.captureSession stopRunning];
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    });
}

/** 处理完一个码之后稍等再开扫，避免马上又扫到同一个码 */
- (void)restartScan {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kQRScannerRestartAfterResolveDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self startScan];
    });
}

/** 弹出图片选择器 */
- (void)showImagePickerController {
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    imagePicker.delegate = self;
    imagePicker.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:imagePicker animated:YES completion:nil];
}

/** 从 UIImage 中读取二维码信息 */
- (void)readQRCodeFromImage:(UIImage *)image {
    if (!image) {
        [self.runtimeState setResolving:NO];
        [self showAlertMessage:@"没有读取到照片"];
        [self restartScan];
        return;
    }
    // 开始识别
    [self.loadingIndicatorView startAnimating];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CIImage *ciImage = [self ciImageWithUIImage:image];
        if (!ciImage) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicatorView stopAnimating];
                [self.runtimeState setResolving:NO];
                [self showAlertMessage:@"没有读取到照片"];
                [self restartScan];
            });
            return;
        }
        
        CIContext *context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @(YES)}];
        CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                                  context:context
                                                  options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
        
        NSArray *features = [detector featuresInImage:ciImage];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // 结束识别
            [self.loadingIndicatorView stopAnimating];
            
            if (0 == features.count) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                               message:@"照片中未识别到二维码"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                    [self.runtimeState setResolving:NO];
                    [self restartScan];
                }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"重选" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [self showImagePickerController];
                }]];
                [self presentViewController:alert animated:YES completion:nil];
            } else if (1 == features.count) {
                // 识别到一个二维码
                CIQRCodeFeature *feature = [features firstObject];
                [self resolveQrCodeWithStringValue:feature.messageString];
            } else {
                // 识别到多个二维码
                [self showCodePickerWithCameraCodes:nil imageFeatures:features image:image];
            }
        });
    });
}

/** 展示二维码选择页面, cameraCodes 和 imageFeatures 二选一, 图片识别模式要传 image */
- (void)showCodePickerWithCameraCodes:(NSArray *)cameraCodes
                                 imageFeatures:(NSArray *)imageFeatures
                                        image:(UIImage *)image {
    QRCodePickerView *codePickerView = [[QRCodePickerView alloc] init];
    codePickerView.cameraCodes = cameraCodes;
    codePickerView.imageFeatures = imageFeatures;
    codePickerView.image = image;
    codePickerView.sourcePreviewLayer = image ? nil : self.captureVideoPreviewLayer;
    codePickerView.delegate = self;
    [codePickerView showInView:self.view];
    
    self.codePickerView = codePickerView;
}

/** 把识别出的原文交给调用方。未设置回调时就地展示，并允许继续扫描 */
- (void)resolveQrCodeWithStringValue:(NSString *)stringValue {
    NSString *codeString = stringValue ?: @"";
    if (self.onCodeRecognized) {
        self.onCodeRecognized(self, codeString);
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"识别结果"
                                                                   message:codeString
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"继续扫描" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self resumeScanning];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (CIImage *)ciImageWithUIImage:(UIImage *)image {
    if (!image) return nil;
    
    if (UIImageOrientationUp == image.imageOrientation) {
        CIImage *ciImage = [[CIImage alloc] initWithCGImage:image.CGImage];
        return ciImage;
    }
    
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    UIImage *normalizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CIImage *ciImage = [[CIImage alloc] initWithCGImage:normalizedImage.CGImage];
    return ciImage;
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)cameraCodes
       fromConnection:(AVCaptureConnection *)connection {
    if (0 == cameraCodes.count) return;
    QRScannerStateSnapshot *runtimeSnapshot = [self.runtimeState snapshot];
    if (!runtimeSnapshot.isScanning || runtimeSnapshot.isResolving) return;
    
    NSMutableArray<AVMetadataMachineReadableCodeObject *> *decodedObjects = [NSMutableArray array];
    NSMutableArray<NSValue *> *boxRects = [NSMutableArray array];
    CGRect unionBox = CGRectZero;
    
    for (AVMetadataObject *metadataObject in cameraCodes) {
        if (![metadataObject isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            continue;
        }
        AVMetadataObject *transformedObj = [self.captureVideoPreviewLayer transformedMetadataObjectForMetadataObject:metadataObject];
        if (![transformedObj isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            continue;
        }
        AVMetadataMachineReadableCodeObject *codeObject = (AVMetadataMachineReadableCodeObject *)transformedObj;
        CGRect box = codeObject.bounds;
        if (!CGRectIsEmpty(box)) {
            [boxRects addObject:[NSValue valueWithCGRect:box]];
            unionBox = CGRectIsEmpty(unionBox) ? box : CGRectUnion(unionBox, box);
        }
        if (codeObject.stringValue.length > 0) {
            [decodedObjects addObject:codeObject];
        }
    }
        
    if (CGRectIsEmpty(unionBox) && decodedObjects.count == 0) {
        return;
    }
        
    NSTimeInterval now = CACurrentMediaTime();
    self.pendingVisibleBoxCount = MAX(self.pendingVisibleBoxCount, MAX(boxRects.count, decodedObjects.count));
    [self noteQRRectSeen:CGRectIsEmpty(unionBox) ? decodedObjects.firstObject.bounds : unionBox];

    if (decodedObjects.count == 0) {
        [self requestAutoZoomForDetectedRects:boxRects];
        return;
    }

    [self.runtimeState recordMetadataDecodedAtTime:now];
    for (AVMetadataMachineReadableCodeObject *codeObject in decodedObjects) {
        [self mergePendingDecodedObject:codeObject];
    }
    [self commitOrDeferDecodedResultsVisibleBoxCount:MAX(self.pendingVisibleBoxCount, MAX(boxRects.count, decodedObjects.count))
                                           afterZoom:NO];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    QRScannerStateSnapshot *runtimeSnapshot = [self.runtimeState snapshot];
    if (!runtimeSnapshot.isScanning || runtimeSnapshot.isResolving || runtimeSnapshot.isAutoZooming) {
        return;
    }

    NSTimeInterval now = CACurrentMediaTime();
    NSTimeInterval minInterval = kQRScannerVisionMinInterval;
    if (runtimeSnapshot.lastQRSeenTime > 0.0
        && (now - runtimeSnapshot.lastQRSeenTime) < kQRScannerVisionAfterBoxInterval) {
        minInterval = kQRScannerVisionAfterBoxInterval;
    }
    // 对焦中的画面可能略糊，但仍可能定位到 Finder Pattern；降频处理比完全等待合焦更快。
    if (self.captureDevice.isAdjustingFocus) {
        minInterval = MAX(minInterval, kQRScannerVisionDuringFocusInterval);
    }
    if (now - runtimeSnapshot.lastVisionDetectTime < minInterval) {
        return;
    }
    // 系统刚刚读出内容时，先不再找位置。找位置只在系统还没读出来时做
    if (now - runtimeSnapshot.lastMetadataDecodedTime < kQRScannerMetadataFreshInterval) {
        return;
    }

    QRScannerPreviewGeometry *previewGeometry = self.previewGeometry;
    if (!previewGeometry || CGRectIsEmpty(previewGeometry.previewBounds)) {
        return;
    }
    CGRect visionRectInPreview = previewGeometry.previewBounds;

    [self.runtimeState recordVisionDetectionAtTime:now];
    CGImagePropertyOrientation visionOrientation =
        [QRScannerOrientation visionOrientationForVideoOrientation:connection.videoOrientation];
    NSArray<NSValue *> *qrRects = [self.codeLocator locateQRCodeRectsInSampleBuffer:sampleBuffer
                                                                  previewGeometry:previewGeometry
                                                               visionRectInPreview:visionRectInPreview
                                                                       orientation:visionOrientation];
    if (qrRects.count > 0) {
        [self.runtimeState recordQRCodeSeenAtTime:CACurrentMediaTime()];
    }

    NSUInteger captureGeneration = runtimeSnapshot.captureGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        QRScannerStateSnapshot *mainSnapshot = [self.runtimeState snapshot];
        if (![self.runtimeState isCaptureGenerationCurrent:captureGeneration]
            || !mainSnapshot.isScanning
            || mainSnapshot.isResolving) {
            return;
        }
        if (qrRects.count == 0) {
            return;
        }
        if (self.pendingDecodedObjects.count > 0) {
            return;
        }
        self.pendingVisibleBoxCount = MAX(self.pendingVisibleBoxCount, qrRects.count);
        [self requestAutoZoomForDetectedRects:qrRects];
    });
}

#pragma mark - UIImagePickerControllerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *photo = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        [self readQRCodeFromImage:photo];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{
        [self.runtimeState setResolving:NO];
        [self restartScan];
    }];
}

#pragma mark - QRCodePickerViewDelegate
- (void)pickerView:(QRCodePickerView *)pickerView didSelectCode:(NSString *)codeString {
    self.containerView.hidden = NO;
    
    [self resolveQrCodeWithStringValue:codeString];
}

/** 选择二维码页面, 点击返回 */
- (void)pickerViewDidClose:(QRCodePickerView *)pickerView {
    // 标记为未在处理中
    [self.runtimeState setResolving:NO];
    
    self.containerView.hidden = NO;
    self.ignoreDecodedCommitUntil = CACurrentMediaTime() + kQRScannerIgnoreAfterSelectorClose;
    [self startScan];
}

#pragma mark - Torch / Low Light

- (void)startLowLightMonitoring {
    if (!self.torchSupported || !self.captureDevice) {
        return;
    }
    if (self.lowLightTimer) {
        return;
    }
    
    self.darkSampleCount = 0;
    self.brightSampleCount = 0;
    
    self.lowLightTimer = [QRScannerTimer scheduledTimerWithTimeInterval:kQRScannerLowLightSampleInterval
                                                              target:self
                                                            selector:@selector(handleLowLightSample)
                                                            userInfo:nil
                                                             repeats:YES
                                                       dispatchQueue:dispatch_get_main_queue()];
}

- (void)stopLowLightMonitoring {
    if (self.lowLightTimer) {
        [self.lowLightTimer invalidate];
        self.lowLightTimer = nil;
    }
    self.darkSampleCount = 0;
    self.brightSampleCount = 0;
}

- (void)handleLowLightSample {
    if (!self.torchSupported || !self.captureDevice) {
        return;
    }
    // 灯开时保持按钮可见，不做隐藏判定
    if (self.isTorchOn) {
        [self setTorchButtonVisible:YES animated:YES];
        return;
    }
    
    AVCaptureDevice *device = self.captureDevice;
    float iso = device.ISO;
    NSTimeInterval exposure = CMTimeGetSeconds(device.exposureDuration);
    BOOL isDark = (iso >= kQRScannerLowLightISOThreshold) || (exposure >= kQRScannerLowLightExposureThreshold);
    
    if (isDark) {
        self.darkSampleCount += 1;
        self.brightSampleCount = 0;
        if (self.darkSampleCount >= kQRScannerLowLightShowCount) {
            [self setTorchButtonVisible:YES animated:YES];
        }
    } else {
        self.brightSampleCount += 1;
        self.darkSampleCount = 0;
        if (self.brightSampleCount >= kQRScannerLowLightHideCount) {
            [self setTorchButtonVisible:NO animated:YES];
        }
    }
}

- (void)setTorchButtonVisible:(BOOL)visible animated:(BOOL)animated {
    if (!self.torchSupported) {
        return;
    }
    
    void (^apply)(void) = ^{
        self.torchControl.alpha = visible ? 1.f : 0.f;
        self.torchControl.hidden = !visible;
        self.torchControl.userInteractionEnabled = visible;
    };
    
    if (!animated) {
        apply();
        return;
    }
    
    if (visible) {
        self.torchControl.hidden = NO;
        self.torchControl.userInteractionEnabled = YES;
    }
    [UIView animateWithDuration:0.25f animations:^{
        self.torchControl.alpha = visible ? 1.f : 0.f;
    } completion:^(BOOL finished) {
        if (!visible) {
            self.torchControl.hidden = YES;
            self.torchControl.userInteractionEnabled = NO;
        }
    }];
}

- (void)setTorchOn:(BOOL)on {
    if (!self.torchSupported || !self.captureDevice) {
        self.isTorchOn = NO;
        self.torchControl.torchOn = NO;
        return;
    }
    if (self.isTorchOn == on) {
        self.torchControl.torchOn = on;
        return;
    }
    
    self.isTorchOn = on;
    self.torchControl.torchOn = on;
    
    if (on) {
        [self setTorchButtonVisible:YES animated:YES];
    }
    
    AVCaptureDevice *device = self.captureDevice;
    dispatch_async(self.sessionQueue, ^{
        if (!device.hasTorch || !device.isTorchAvailable) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isTorchOn = NO;
                self.torchControl.torchOn = NO;
            });
            return;
        }
        
        NSError *error = nil;
        if (![device lockForConfiguration:&error]) {
            return;
        }
        device.torchMode = on ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
        [device unlockForConfiguration];
    });
}

- (void)torchButtonTapped:(QRScannerTorchButton *)sender {
    if ([self.runtimeState snapshot].isResolving) {
        return;
    }
    [self setTorchOn:!self.isTorchOn];
}

#pragma mark - Auto Zoom / Focus

/// 记录码框，供拉近后对焦与离开画面复位
- (void)noteQRRectSeen:(CGRect)rect {
    if (CGRectIsEmpty(rect)) {
        return;
    }
    self.lastQRRectInPreview = rect;
    [self.runtimeState recordQRCodeSeenAtTime:CACurrentMediaTime()];
}

/// 按内容去重，后续回调可补上第二码
- (void)mergePendingDecodedObject:(AVMetadataMachineReadableCodeObject *)codeObject {
    if (codeObject.stringValue.length == 0) {
        return;
    }
    if (!self.pendingDecodedObjects) {
        self.pendingDecodedObjects = [NSMutableArray array];
    }
    for (NSUInteger i = 0; i < self.pendingDecodedObjects.count; i++) {
        AVMetadataMachineReadableCodeObject *existing = self.pendingDecodedObjects[i];
        if ([existing.stringValue isEqualToString:codeObject.stringValue]) {
            self.pendingDecodedObjects[i] = codeObject;
            return;
        }
    }
    [self.pendingDecodedObjects addObject:codeObject];
}

/// 多个码的箭头要用拉近结束后系统重新报上来的位置。等太久就用现有位置，避免一直停着
- (BOOL)decodedBoundsMatchCurrentZoom {
    if (self.lastAutoZoomFinishedAt <= 0) {
        return YES;
    }
    QRScannerStateSnapshot *snapshot = [self.runtimeState snapshot];
    if (snapshot.lastMetadataDecodedTime >= self.lastAutoZoomFinishedAt) {
        return YES;
    }
    return (CACurrentMediaTime() - self.lastAutoZoomFinishedAt) >= kQRScannerPostZoomMetadataWait;
}

- (void)scheduleSingleCodeCommitWithInterval:(NSTimeInterval)interval {
    if (self.multiCodeTimer) {
        return;
    }
    self.multiCodeTimer = [QRScannerTimer scheduledTimerWithTimeInterval:interval
                                                               target:self
                                                             selector:@selector(finishWithPendingDecodedCodes)
                                                             userInfo:nil
                                                              repeats:NO
                                                        dispatchQueue:dispatch_get_main_queue()];
}

/**
 系统已解出时：拉近开始前立刻跳转；拉近请求还没完成，或镜头还在拉近时，先等倍率稳定。
 多个框但只解出一码时短等第二码；单框单码不等待。
 */
- (void)commitOrDeferDecodedResultsVisibleBoxCount:(NSUInteger)boxCount afterZoom:(BOOL)afterZoom {
    if (self.pendingDecodedObjects.count == 0) {
        return;
    }
    QRScannerStateSnapshot *snapshot = [self.runtimeState snapshot];
    if (snapshot.isAutoZooming || snapshot.isZoomRequestInFlight) {
        if (self.multiCodeTimer) {
            [self.multiCodeTimer invalidate];
            self.multiCodeTimer = nil;
        }
        return;
    }
    if (self.pendingDecodedObjects.count > 1) {
        [self finishWithPendingDecodedCodes];
        return;
    }
    if (boxCount > 1) {
        NSTimeInterval wait = afterZoom ? kQRScannerMultiCodeAfterZoomWaitInterval : kQRScannerMultiCodeWaitInterval;
        [self scheduleSingleCodeCommitWithInterval:wait];
        return;
    }
    [self finishWithPendingDecodedCodes];
}

- (void)finishWithPendingDecodedCodes {
    if (self.multiCodeTimer) {
        [self.multiCodeTimer invalidate];
        self.multiCodeTimer = nil;
    }
    QRScannerStateSnapshot *snapshot = [self.runtimeState snapshot];
    if (!snapshot.isScanning || snapshot.isResolving) {
        return;
    }
    if (CACurrentMediaTime() < self.ignoreDecodedCommitUntil) {
        return;
    }
    if (self.pendingDecodedObjects.count > 1
        && ![self decodedBoundsMatchCurrentZoom]) {
        [self scheduleSingleCodeCommitWithInterval:kQRScannerPostZoomMetadataRetryInterval];
        return;
    }
    NSArray<AVMetadataMachineReadableCodeObject *> *codes = [self.pendingDecodedObjects copy];
    if (codes.count == 0) {
        return;
    }

    [self.runtimeState setResolving:YES];

    if (codes.count > 1) {
        // 选择器箭头用的是拉近后的 Preview 坐标；停下相机时不能把倍率退回默认，否则停住的画面和箭头会对不齐
        NSArray<AVMetadataMachineReadableCodeObject *> *selectorCodes = codes;
        __weak typeof(self) weakSelf = self;
        [self stopScanResettingPreviewZoom:NO completion:^{
            QRCodeScannerViewController *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            if (!strongSelf.preservePreviewZoomForPicker
                || !strongSelf.isViewLoaded
                || !strongSelf.view.window
                || strongSelf.isMovingFromParentViewController
                || strongSelf.isBeingDismissed) {
                strongSelf.preservePreviewZoomForPicker = NO;
                [strongSelf.runtimeState setResolving:NO];
                return;
            }
            // 等画面停稳再藏起扫描页按钮并弹出选择层，避免返回按钮闪一下
            strongSelf.containerView.hidden = YES;
            [strongSelf showCodePickerWithCameraCodes:selectorCodes imageFeatures:nil image:nil];
        }];
        return;
    }

    [self stopScan];
    [self resolveQrCodeWithStringValue:codes.firstObject.stringValue];
}

- (void)clearPendingDecodedCodes {
    if (self.multiCodeTimer) {
        [self.multiCodeTimer invalidate];
        self.multiCodeTimer = nil;
    }
    [self.pendingDecodedObjects removeAllObjects];
    self.pendingVisibleBoxCount = 0;
}

/// 旋转或 Preview 几何变化时丢弃旧方向上的待提交码和对焦框
- (void)invalidatePendingScanResultsForGeometryChange {
    self.lastQRRectInPreview = CGRectZero;
    [self clearPendingDecodedCodes];
}

/// 仅在主线程采样 PreviewLayer，供 Vision 队列做坐标映射
- (void)refreshPreviewGeometry {
    self.previewGeometry = [QRScannerPreviewGeometry geometryFromPreviewLayer:self.captureVideoPreviewLayer];
}

/// 按检出框拉近；多码用最大码宽限制目标倍率，并用联合框保证所有码都留在安全区内
- (void)requestAutoZoomForDetectedRects:(NSArray<NSValue *> *)rects {
    if (self.pendingDecodedObjects.count > 0) {
        return;
    }
    self.pendingVisibleBoxCount = MAX(self.pendingVisibleBoxCount, rects.count);
    CGRect unionRect = CGRectZero;
    CGFloat maxWidth = 0.f;
    for (NSValue *value in rects) {
        CGRect rect = value.CGRectValue;
        if (CGRectIsEmpty(rect) || rect.size.width < 1.f) {
            continue;
        }
        unionRect = CGRectIsEmpty(unionRect) ? rect : CGRectUnion(unionRect, rect);
        maxWidth = MAX(maxWidth, rect.size.width);
    }
    if (CGRectIsEmpty(unionRect)) {
        return;
    }
    // 多码的几何中心是稳定目标，不依赖 Metadata 或 Vision 返回数组的顺序。
    [self noteQRRectSeen:unionRect];
    [self requestAutoZoomForUnionRect:unionRect maxQRWidth:maxWidth];
}

/// 每次拿到新码框都重新计算目标倍率；允许连续自动变焦，但两次拉近至少间隔 0.5s，且同一时刻只执行一次
- (void)requestAutoZoomForUnionRect:(CGRect)unionRect maxQRWidth:(CGFloat)maxQRWidth {
    QRScannerStateSnapshot *snapshot = [self.runtimeState snapshot];
    if (!snapshot.isScanning
        || snapshot.isResolving
        || snapshot.isAutoZooming
        || snapshot.isZoomRequestInFlight) {
        return;
    }
    if (self.pendingDecodedObjects.count > 0) {
        return;
    }
    if (self.lastAutoZoomFinishedAt > 0
        && (CACurrentMediaTime() - self.lastAutoZoomFinishedAt) < kQRScannerAutoZoomMinInterval) {
        return;
    }
    if (CGRectIsEmpty(unionRect) || maxQRWidth < 1.f) {
        return;
    }
    if (maxQRWidth >= kQRScannerAutoZoomMaxCodeWidth) {
        return;
    }

    AVCaptureDevice *device = self.captureDevice;
    if (!device) {
        return;
    }

    CGRect previewBounds = self.captureVideoPreviewLayer.bounds;
    NSUInteger generation = [self.runtimeState beginAutoZoomRequest];

    dispatch_async(self.sessionQueue, ^{
        QRScannerStateSnapshot *sessionSnapshot = [self.runtimeState snapshot];
        if (![self.runtimeState isAutoZoomGenerationCurrent:generation]
            || !sessionSnapshot.isScanning
            || sessionSnapshot.isResolving) {
            return;
        }

        CGFloat currentZoom = device.videoZoomFactor;
        CGFloat wideBaseZoom = [self wideLensBaseVideoZoomFactorForDevice:device];
        CGFloat currentWideEquivalentZoom = currentZoom / wideBaseZoom;
        CGFloat desiredWideEquivalentZoom = currentWideEquivalentZoom
            * kQRScannerAutoZoomMaxCodeWidth
            / maxQRWidth;
        CGFloat desiredZoom = [self deviceZoomFactorForWideEquivalent:desiredWideEquivalentZoom
                                                                  device:device];
        // 系统变焦围绕预览中心裁切，因此用多码联合框统一限制四边安全区。
        CGFloat maxKeepOnScreen = [self maxZoomFactorKeepingRect:unionRect
                                                     previewBounds:previewBounds
                                                       currentZoom:currentZoom];
        CGFloat targetZoom = [self clampedAutoZoomFactor:MIN(desiredZoom, maxKeepOnScreen)
                                                    device:device];
        targetZoom = MIN(targetZoom, maxKeepOnScreen);
        if (targetZoom <= currentZoom + 0.08f) {
            [self.runtimeState finishAutoZoomForGeneration:generation];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.pendingDecodedObjects.count > 0) {
                    [self commitOrDeferDecodedResultsVisibleBoxCount:MAX(self.pendingVisibleBoxCount, self.pendingDecodedObjects.count)
                                                           afterZoom:NO];
                }
            });
            return;
        }
        if (![self.runtimeState markAutoZoomStartedForGeneration:generation]) {
            return;
        }

        NSError *error = nil;
        if (![device lockForConfiguration:&error]) {
            [self.runtimeState finishAutoZoomForGeneration:generation];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.pendingDecodedObjects.count > 0) {
                    [self commitOrDeferDecodedResultsVisibleBoxCount:MAX(self.pendingVisibleBoxCount, self.pendingDecodedObjects.count)
                                                           afterZoom:NO];
                }
            });
            return;
        }
        [device rampToVideoZoomFactor:targetZoom withRate:kQRScannerZoomRampRate];
        [device unlockForConfiguration];

        [self pollZoomRampFinishedForDevice:device
                                 generation:generation
                          hasStartedRamping:device.isRampingVideoZoom
                                  startedAt:CACurrentMediaTime()
                    consecutiveSettledCount:0];
    });
}

/// 系统 videoZoomFactor 只能绕预览中心裁切。按联合框四边相对中心的距离，算出保留固定 20pt 边距的最大倍率
- (CGFloat)maxZoomFactorKeepingRect:(CGRect)rect
                         previewBounds:(CGRect)previewBounds
                           currentZoom:(CGFloat)currentZoom {
    if (CGRectIsEmpty(previewBounds) || CGRectIsEmpty(rect) || currentZoom < 0.01f) {
        return currentZoom;
    }
    CGRect visible = CGRectInset(previewBounds,
                                 kQRScannerZoomKeepOnScreenInset,
                                 kQRScannerZoomKeepOnScreenInset);
    if (visible.size.width < 1.f || visible.size.height < 1.f) {
        return currentZoom;
    }
    // 当前联合框已经侵入安全边距时，放大只会让它更靠近屏幕外，因此保持当前焦距。
    if (!CGRectContainsRect(visible, rect)) {
        return currentZoom;
    }
    CGPoint center = CGPointMake(CGRectGetMidX(previewBounds), CGRectGetMidY(previewBounds));
    CGFloat maxScale = CGFLOAT_MAX;

    CGFloat leftDist = center.x - CGRectGetMinX(rect);
    CGFloat leftRoom = center.x - CGRectGetMinX(visible);
    if (leftDist > 0.5f) {
        maxScale = MIN(maxScale, leftRoom / leftDist);
    }
    CGFloat rightDist = CGRectGetMaxX(rect) - center.x;
    CGFloat rightRoom = CGRectGetMaxX(visible) - center.x;
    if (rightDist > 0.5f) {
        maxScale = MIN(maxScale, rightRoom / rightDist);
    }
    CGFloat topDist = center.y - CGRectGetMinY(rect);
    CGFloat topRoom = center.y - CGRectGetMinY(visible);
    if (topDist > 0.5f) {
        maxScale = MIN(maxScale, topRoom / topDist);
    }
    CGFloat bottomDist = CGRectGetMaxY(rect) - center.y;
    CGFloat bottomRoom = CGRectGetMaxY(visible) - center.y;
    if (bottomDist > 0.5f) {
        maxScale = MIN(maxScale, bottomRoom / bottomDist);
    }

    if (maxScale == CGFLOAT_MAX) {
        return CGFLOAT_MAX;
    }
    if (maxScale <= 1.f) {
        return currentZoom;
    }
    return currentZoom * maxScale;
}

- (CGFloat)clampedAutoZoomFactor:(CGFloat)desired device:(AVCaptureDevice *)device {
    CGFloat minZoom = device.minAvailableVideoZoomFactor;
    CGFloat maxZoom = [self maxAutoZoomVideoFactorForDevice:device];
    return MIN(MAX(desired, minZoom), maxZoom);
}

/// 将产品定义的广角等效倍率转换为当前虚拟设备实际使用的 videoZoomFactor
- (CGFloat)deviceZoomFactorForWideEquivalent:(CGFloat)wideEquivalent
                                          device:(AVCaptureDevice *)device {
    return wideEquivalent * [self wideLensBaseVideoZoomFactorForDevice:device];
}

/// DualWide/Triple 的 videoZoomFactor=1 通常是超广角，广角镜头对应倍率需统一换算
- (CGFloat)wideLensBaseVideoZoomFactorForDevice:(AVCaptureDevice *)device {
    if (!device) {
        return 1.f;
    }
    if (@available(iOS 18.0, *)) {
        CGFloat multiplier = device.displayVideoZoomFactorMultiplier;
        if (multiplier > 0.01f) {
            return 1.f / multiplier;
        }
    }

    AVCaptureDeviceType type = device.deviceType;
    BOOL usesUltraWideAsOne = [type isEqualToString:AVCaptureDeviceTypeBuiltInDualWideCamera]
        || [type isEqualToString:AVCaptureDeviceTypeBuiltInTripleCamera]
        || [type isEqualToString:AVCaptureDeviceTypeBuiltInUltraWideCamera];
    if (!usesUltraWideAsOne) {
        return 1.f;
    }
    CGFloat wideFactor = device.virtualDeviceSwitchOverVideoZoomFactors.firstObject.floatValue;
    return wideFactor >= 1.01f ? wideFactor : 2.f;
}

/// 自动变焦上限同样以广角镜头为基准，避免不同虚拟设备获得不同视野
- (CGFloat)maxAutoZoomVideoFactorForDevice:(AVCaptureDevice *)device {
    if (!device) {
        return kQRScannerMaxAutoZoomFactor;
    }
    CGFloat hardwareMax = device.maxAvailableVideoZoomFactor;
    CGFloat equivalentMax = [self deviceZoomFactorForWideEquivalent:kQRScannerMaxAutoZoomFactor
                                                                 device:device];
    if (equivalentMax < device.minAvailableVideoZoomFactor) {
        equivalentMax = device.minAvailableVideoZoomFactor;
    }
    return MIN(equivalentMax, hardwareMax);
}

- (void)pollZoomRampFinishedForDevice:(AVCaptureDevice *)device
                           generation:(NSUInteger)generation
                    hasStartedRamping:(BOOL)hasStartedRamping
                            startedAt:(NSTimeInterval)startedAt
              consecutiveSettledCount:(NSUInteger)consecutiveSettledCount {
    if (![self.runtimeState isAutoZoomGenerationCurrent:generation]) {
        return;
    }
    BOOL ramping = device.isRampingVideoZoom;
    BOOL started = hasStartedRamping || ramping;
    BOOL startTimeout = (CACurrentMediaTime() - startedAt) >= kQRScannerZoomRampStartTimeout;
    if (ramping || (!started && !startTimeout)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), self.sessionQueue, ^{
            [self pollZoomRampFinishedForDevice:device
                                     generation:generation
                              hasStartedRamping:started
                                      startedAt:startedAt
                        consecutiveSettledCount:0];
        });
        return;
    }

    NSUInteger settledCount = consecutiveSettledCount + 1;
    if (settledCount < kQRScannerZoomRampSettledPolls) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), self.sessionQueue, ^{
            [self pollZoomRampFinishedForDevice:device
                                     generation:generation
                              hasStartedRamping:YES
                                      startedAt:startedAt
                        consecutiveSettledCount:settledCount];
        });
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        QRScannerStateSnapshot *snapshot = [self.runtimeState snapshot];
        if (![self.runtimeState isAutoZoomGenerationCurrent:generation]
            || !snapshot.isScanning
            || snapshot.isResolving) {
            [self.runtimeState finishAutoZoomForGeneration:generation];
            return;
        }
        self.lastAutoZoomFinishedAt = CACurrentMediaTime();
        [self.runtimeState finishAutoZoomForGeneration:generation];
        if (self.pendingDecodedObjects.count > 0) {
            [self commitOrDeferDecodedResultsVisibleBoxCount:MAX(self.pendingVisibleBoxCount, self.pendingDecodedObjects.count)
                                                   afterZoom:YES];
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kQRScannerFocusAfterRampDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            QRScannerStateSnapshot *delayedSnapshot = [self.runtimeState snapshot];
            if (![self.runtimeState isAutoZoomGenerationCurrent:generation]
                || !delayedSnapshot.isScanning
                || delayedSnapshot.isResolving) {
                return;
            }
            [self updateContinuousFocusForLatestQR];
        });
    });
}

/// 场景远近变化时，把 ContinuousAF 对焦点打到当前码心或画面中心并重新测距
- (void)captureDeviceSubjectAreaDidChange:(NSNotification *)notification {
    if (notification.object != self.captureDevice) {
        return;
    }
    [self updateContinuousFocusForLatestQR];
}

/// 有码框则对码心，否则对 Preview 中心
- (void)updateContinuousFocusForLatestQR {
    CGRect qrRect = self.lastQRRectInPreview;
    CGRect previewBounds = self.captureVideoPreviewLayer.bounds;
    CGPoint center;
    if (!CGRectIsEmpty(qrRect)) {
        center = CGPointMake(CGRectGetMidX(qrRect), CGRectGetMidY(qrRect));
    } else if (!CGRectIsEmpty(previewBounds)) {
        center = CGPointMake(CGRectGetMidX(previewBounds), CGRectGetMidY(previewBounds));
    } else {
        return;
    }
    [self updateContinuousFocusAtPreviewPoint:center];
}

/// Preview 中心 → 设备归一化对焦点；几何未就绪时用 (0.5, 0.5)
- (CGPoint)currentFocusDevicePoint {
    AVCaptureVideoPreviewLayer *layer = self.captureVideoPreviewLayer;
    if (!layer || CGRectIsEmpty(layer.bounds)) {
        return CGPointMake(0.5f, 0.5f);
    }
    CGPoint center = CGPointMake(CGRectGetMidX(layer.bounds), CGRectGetMidY(layer.bounds));
    CGPoint devicePoint = [layer captureDevicePointOfInterestForPoint:center];
    devicePoint.x = MIN(MAX(devicePoint.x, 0.f), 1.f);
    devicePoint.y = MIN(MAX(devicePoint.y, 0.f), 1.f);
    return devicePoint;
}

/// 将 ContinuousAF 对焦点写到 preview 点；已是 CAF 时再写一次以触发重新测距
- (void)updateContinuousFocusAtPreviewPoint:(CGPoint)previewPoint {
    AVCaptureDevice *device = self.captureDevice;
    AVCaptureVideoPreviewLayer *previewLayer = self.captureVideoPreviewLayer;
    QRScannerStateSnapshot *snapshot = [self.runtimeState snapshot];
    if (!device || !snapshot.isScanning || snapshot.isResolving || snapshot.isAutoZooming) {
        return;
    }
    CGPoint devicePoint = CGPointMake(0.5f, 0.5f);
    if (previewLayer && !CGRectIsEmpty(previewLayer.bounds) && previewPoint.x >= 0.f && previewPoint.y >= 0.f) {
        devicePoint = [previewLayer captureDevicePointOfInterestForPoint:previewPoint];
        devicePoint.x = MIN(MAX(devicePoint.x, 0.f), 1.f);
        devicePoint.y = MIN(MAX(devicePoint.y, 0.f), 1.f);
    }
    dispatch_async(self.sessionQueue, ^{
        [self applyContinuousFocusAtDevicePoint:devicePoint device:device];
    });
}

/// 已在 sessionQueue：只维持 ContinuousAF，不打单次 AutoFocus
- (void)applyContinuousFocusAtDevicePoint:(CGPoint)devicePoint device:(AVCaptureDevice *)device {
    QRScannerStateSnapshot *snapshot = [self.runtimeState snapshot];
    if (!device || !self.captureSession.isRunning || !snapshot.isScanning || snapshot.isResolving) {
        return;
    }
    if (snapshot.isAutoZooming || device.isRampingVideoZoom) {
        return;
    }
    NSError *error = nil;
    if (![device lockForConfiguration:&error]) {
        return;
    }
    if (device.isFocusPointOfInterestSupported) {
        device.focusPointOfInterest = devicePoint;
    }
    if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
    }
    [device unlockForConfiguration];
}

/// 取消正在进行的拉近，倍率停在当前画面，不退回默认倍率
- (void)cancelZoomRampKeepingCurrentFactor {
    AVCaptureDevice *device = self.captureDevice;
    if (!device) {
        return;
    }
    NSError *error = nil;
    if (![device lockForConfiguration:&error]) {
        return;
    }
    if (device.isRampingVideoZoom) {
        [device cancelVideoZoomRamp];
    }
    [device unlockForConfiguration];
}

/**
 复位广角等效默认倍率，并对画面中心维持 ContinuousAF。
 必须在 sessionQueue 上调用。

 @param devicePoint 主线程根据 Preview 几何预先换算的设备对焦点
 */
- (void)resetZoomAndFocusToDefaultLockedWithDevicePoint:(CGPoint)devicePoint {
    AVCaptureDevice *device = self.captureDevice;
    if (!device) {
        return;
    }
    NSError *error = nil;
    if (![device lockForConfiguration:&error]) {
        return;
    }
    if (device.isRampingVideoZoom) {
        [device cancelVideoZoomRamp];
    }
    CGFloat minZoom = device.minAvailableVideoZoomFactor;
    CGFloat maxZoom = device.maxAvailableVideoZoomFactor;
    CGFloat wideEquivalentZoom = [self deviceZoomFactorForWideEquivalent:kQRScannerDefaultZoomFactor
                                                                      device:device];
    CGFloat targetZoom = MIN(MAX(wideEquivalentZoom, minZoom), maxZoom);
    if (fabs(device.videoZoomFactor - targetZoom) > 0.01f) {
        device.videoZoomFactor = targetZoom;
    }
    if (device.isFocusPointOfInterestSupported) {
        device.focusPointOfInterest = devicePoint;
    }
    if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
    }
    [device unlockForConfiguration];
}

#pragma mark - User Actions
- (void)backButtonTapped:(UIButton *)sender {
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)albumButtonTapped:(UIButton *)sender {
    if ([self.runtimeState snapshot].isResolving) {
        return;
    }

    [self stopScan];
    [self.runtimeState setResolving:YES];

    __weak typeof(self) weakSelf = self;
    void (^openPicker)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf showImagePickerController];
        });
    };
    void (^abort)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            QRCodeScannerViewController *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf.runtimeState setResolving:NO];
            [strongSelf restartScan];
        });
    };

    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
        openPicker();
        return;
    }
    if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus newStatus) {
            if (newStatus == PHAuthorizationStatusAuthorized || newStatus == PHAuthorizationStatusLimited) {
                openPicker();
            } else {
                abort();
            }
        }];
        return;
    }
    [self showAlertMessage:@"请在系统设置中允许访问相册后再从图片识别二维码"];
    abort();
}

#pragma mark - Notifications
- (void)appWillEnterForegroundNotification {
    [self updateCaptureOrientation];
    [self startScan];
}

- (void)appDidEnterBackgroundNotification {
    [self stopScan];
}

/// 优先读取当前页面所在 Scene；viewDidLoad 尚未挂到 Window 时再取前台 Scene
- (UIInterfaceOrientation)currentInterfaceOrientation {
    UIWindowScene *windowScene = self.view.window.windowScene;
    if (!windowScene) {
        windowScene = self.navigationController.view.window.windowScene;
    }
    if (!windowScene) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            if (scene.activationState == UISceneActivationStateForegroundActive
                || scene.activationState == UISceneActivationStateForegroundInactive) {
                windowScene = (UIWindowScene *)scene;
                break;
            }
        }
    }
    return windowScene ? windowScene.interfaceOrientation : UIInterfaceOrientationUnknown;
}

/**
 将 Scene 界面方向统一同步到 Preview、Metadata 和 VideoData 连接

 @discussion 使用 UIInterfaceOrientation 作为权威来源，避免 UIDeviceOrientation 横屏语义相反。
 旋转前的 Vision 帧和 zoom 延迟任务通过 generation 立即失效。
 */
- (void)updateCaptureOrientation {
    UIInterfaceOrientation interfaceOrientation = [self currentInterfaceOrientation];
    AVCaptureVideoOrientation videoOrientation =
        [QRScannerOrientation videoOrientationForInterfaceOrientation:interfaceOrientation
                                                                        fallback:self.currentVideoOrientation];
    self.currentVideoOrientation = videoOrientation;

    AVCaptureConnection *previewConnection = self.captureVideoPreviewLayer.connection;
    if (previewConnection.isVideoOrientationSupported) {
        previewConnection.videoOrientation = videoOrientation;
    }

    AVCaptureConnection *metadataConnection = [self.captureMetadataOutput connectionWithMediaType:AVMediaTypeMetadata];
    if (metadataConnection.isVideoOrientationSupported) {
        metadataConnection.videoOrientation = videoOrientation;
    }
    AVCaptureConnection *videoConnection = [self.captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    if (videoConnection.isVideoOrientationSupported) {
        videoConnection.videoOrientation = videoOrientation;
    }

    [self.runtimeState invalidateCaptureGeneration];
    [self.runtimeState invalidateAutoZoom];
    [self resetQRCodeLocator];
    [self refreshPreviewGeometry];
    [self updateRectOfInterest];
}

#pragma mark - Private Methods

/// 拿到相机权限后再打开相机。没有相机时，仍然可以从相册选图识别
- (void)requestCameraPermissionThenStart {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        [self launchScan];
        return;
    }
    if (status == AVAuthorizationStatusNotDetermined) {
        __weak typeof(self) weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                QRCodeScannerViewController *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                if (granted) {
                    [strongSelf launchScan];
                } else {
                    [strongSelf showCameraPermissionAlert];
                }
            });
        }];
        return;
    }
    [self showCameraPermissionAlert];
}

- (void)showPendingAlertIfNeeded {
    if (self.needsCameraDeniedAlert && self.view.window && !self.presentedViewController) {
        self.needsCameraDeniedAlert = NO;
        [self showCameraPermissionAlert];
        return;
    }
    if (self.pendingAlertMessage.length == 0 || !self.view.window || self.presentedViewController) {
        return;
    }
    NSString *message = self.pendingAlertMessage;
    self.pendingAlertMessage = nil;
    [self showAlertMessage:message];
}

- (void)showCameraPermissionAlert {
    if (!self.view.window) {
        self.needsCameraDeniedAlert = YES;
        return;
    }
    if (self.presentedViewController) {
        self.needsCameraDeniedAlert = YES;
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法使用相机"
                                                                   message:@"请在系统设置中允许访问相机后再扫描。相册识码仍可使用。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"去设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if (!url) {
            return;
        }
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAlertMessage:(NSString *)message {
    if (message.length == 0) {
        return;
    }
    if (!self.view.window || self.presentedViewController) {
        self.pendingAlertMessage = message;
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Getters
- (dispatch_queue_t)sessionQueue {
    return _sessionQueue?: (_sessionQueue = ({
        dispatch_queue_t sessionQueue = dispatch_queue_create("scan_session_queue", DISPATCH_QUEUE_SERIAL);
        sessionQueue;
    }));
}

- (UIView *)containerView {
    return _containerView?: (_containerView = ({
        UIView *view = [[UIView alloc] init];
        view;
    }));
}

- (UIButton *)backButton {
    return _backButton ?: (_backButton = ({
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        [button setImage:[UIImage imageNamed:@"nav_back_round"] forState:UIControlStateNormal];
        button.accessibilityLabel = @"返回";
        [button addTarget:self action:@selector(backButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        button;
    }));
}

- (AVCaptureSession *)captureSession {
    return _captureSession?: (_captureSession = ({
        AVCaptureSession *session = [[AVCaptureSession alloc] init];
        [session setSessionPreset:AVCaptureSessionPresetHigh];
        session;
    }));
}

- (AVCaptureVideoPreviewLayer *)captureVideoPreviewLayer {
    return _captureVideoPreviewLayer?: (_captureVideoPreviewLayer = ({
        AVCaptureVideoPreviewLayer *layer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
        layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        layer;
    }));
}

- (AVCaptureMetadataOutput *)captureMetadataOutput {
    return _captureMetadataOutput?: (_captureMetadataOutput = ({
        AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
        [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
        output;
    }));
}

- (AVCaptureVideoDataOutput *)captureVideoDataOutput {
    return _captureVideoDataOutput ?: (_captureVideoDataOutput = ({
        AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
        output.alwaysDiscardsLateVideoFrames = YES;
        output.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
        [output setSampleBufferDelegate:self queue:self.visionQueue];
        output;
    }));
}

- (QRCodeLocator *)codeLocator {
    return _codeLocator ?: (_codeLocator = ({
        QRCodeLocator *locator = [[QRCodeLocator alloc] init];
        locator;
    }));
}

- (QRScannerState *)runtimeState {
    return _runtimeState ?: (_runtimeState = [[QRScannerState alloc] init]);
}

- (dispatch_queue_t)visionQueue {
    return _visionQueue ?: (_visionQueue = ({
        dispatch_queue_t queue = dispatch_queue_create("scan_vision_queue", DISPATCH_QUEUE_SERIAL);
        queue;
    }));
}

- (UIView *)scanPane {
    return _scanPane?: (_scanPane = ({
        UIView *view = [[UIView alloc] init];
        [view addSubview:self.scanLine];
        view;
    }));
}

- (UIImageView *)scanLine {
    return _scanLine?: (_scanLine = ({
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.image = [UIImage imageNamed:@"qrcode_scanner_line"];
        imageView;
    }));
}

- (UIActivityIndicatorView *)loadingIndicatorView {
    return _loadingIndicatorView?: (_loadingIndicatorView = ({
        UIActivityIndicatorView *view = [[UIActivityIndicatorView alloc] init];
        view.alpha = .5f;
        view;
    }));
}

- (UIImageView *)hintImageView {
    return _hintImageView?: (_hintImageView = ({
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.image = [UIImage imageNamed:@"qrcode_scanner_remaind"];
        imageView;
    }));
}

- (UIButton *)albumButton {
    return _albumButton?: (_albumButton = ({
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        [button setImage:[UIImage imageNamed:@"qrcode_scanner_album"] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(albumButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        button;
    }));
}

- (QRScannerTorchButton *)torchControl {
    return _torchControl ?: (_torchControl = ({
        QRScannerTorchButton *control = [[QRScannerTorchButton alloc] init];
        control.alpha = 0.f;
        control.hidden = YES;
        control.userInteractionEnabled = NO;
        [control addTarget:self action:@selector(torchButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        control;
    }));
}

- (AVCaptureDevice *)getBestCameraDevice {
    NSArray *deviceTypes = @[];
    if (@available(iOS 13.0, *)) {
        // 优先级从高到低：三摄 -> 双广角 -> 双摄 -> 广角镜头
        deviceTypes = @[AVCaptureDeviceTypeBuiltInTripleCamera,
                        AVCaptureDeviceTypeBuiltInDualWideCamera,
                        AVCaptureDeviceTypeBuiltInDualCamera,
                        AVCaptureDeviceTypeBuiltInWideAngleCamera];
    } else {
        deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera];
    }
    
    AVCaptureDeviceDiscoverySession *session = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes
                                                                                                      mediaType:AVMediaTypeVideo
                                                                                                       position:AVCaptureDevicePositionBack];
    
    // 返回找到的第一个符合要求的设备
    AVCaptureDevice *device = session.devices.firstObject;
    if (!device) {
        // 如果没找到多摄像头设备，回退到默认的广角镜头
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    
    return device;
}

/** 被动成像优化：ContinuousAF、Continuous AE/AWB、近场限制、平滑对焦、低光增强 */
- (void)configureCaptureDevice:(AVCaptureDevice *)device {
    if (!device) {
        return;
    }
    
    NSError *error = nil;
    if (![device lockForConfiguration:&error]) {
        return;
    }
    
    // 自动白平衡
    if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance]) {
        [device setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
    }
    // 进页默认近场对焦，后续扫描、变焦和对焦都不再改写该限制。
    if (device.isAutoFocusRangeRestrictionSupported) {
        device.autoFocusRangeRestriction = AVCaptureAutoFocusRangeRestrictionNear;
    }
    if (device.isFocusPointOfInterestSupported) {
        device.focusPointOfInterest = CGPointMake(0.5f, 0.5f);
    }
    if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
    }
    device.subjectAreaChangeMonitoringEnabled = YES;
    // 平滑对焦
    if (device.isSmoothAutoFocusSupported) {
        device.smoothAutoFocusEnabled = YES;
    }
    // 自动曝光
    if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
        [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
    // 暗光增强（非手电筒）
    if (device.isLowLightBoostSupported) {
        device.automaticallyEnablesLowLightBoostWhenAvailable = YES;
    }
    
    [device unlockForConfiguration];
}

/** 扫描动画 */
- (CAAnimationGroup *)moveAnimation {
    CGFloat lineHeight = CGRectGetHeight(self.scanLine.bounds);
    CGPoint starPoint = CGPointMake(self.scanLine.center.x, lineHeight / 2.f - 40.f);
    CGPoint endPoint = CGPointMake(self.scanLine.center.x, CGRectGetHeight(self.scanPane.bounds) - lineHeight / 2.f);
    
    CABasicAnimation *translation = [CABasicAnimation animationWithKeyPath:@"position"];
    translation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    translation.fromValue = [NSValue valueWithCGPoint:starPoint];
    translation.toValue = [NSValue valueWithCGPoint:endPoint];
    translation.duration = AnimationTime;
    
    CABasicAnimation *opacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity.fromValue = [NSNumber numberWithFloat:1.f];
    opacity.toValue = [NSNumber numberWithFloat:0.f];
    opacity.beginTime = AnimationTime - .3f;
    opacity.duration = .3f;
    
    CAAnimationGroup *groupAnimation = [CAAnimationGroup animation];
    groupAnimation.animations = @[translation, opacity];
    groupAnimation.duration = AnimationTime;
    groupAnimation.repeatCount = CGFLOAT_MAX;
    return groupAnimation;
}

- (void)dealloc {
    [self.runtimeState invalidateAutoZoom];
    [self clearPendingDecodedCodes];
    [self.lowLightTimer invalidate];
    self.lowLightTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
