//
//  iOS-PDF-ReaderViewController.m
//  iOS-PDF-Reader
//
//  Created by Jonathan Wight on 02/19/11.
//  Copyright 2012 Jonathan Wight. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification, are
//  permitted provided that the following conditions are met:
//
//     1. Redistributions of source code must retain the above copyright notice, this list of
//        conditions and the following disclaimer.
//
//     2. Redistributions in binary form must reproduce the above copyright notice, this list
//        of conditions and the following disclaimer in the documentation and/or other materials
//        provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY JONATHAN WIGHT ``AS IS'' AND ANY EXPRESS OR IMPLIED
//  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
//  FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL JONATHAN WIGHT OR
//  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
//  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
//  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
//  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  The views and conclusions contained in the software and documentation are those of the
//  authors and should not be interpreted as representing official policies, either expressed
//  or implied, of Jonathan Wight.

#import "CPDFDocumentViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "CPDFDocument.h"
#import "CPDFPageViewController.h"
#import "CPDFPage.h"
#import "CPDFPageView.h"
#import "CContentScrollView.h"
#import "Geometry.h"
#import "CPreviewCollectionViewCell.h"

@interface CPDFDocumentViewController () <CPDFDocumentDelegate, UIPageViewControllerDelegate, UIPageViewControllerDataSource, UIGestureRecognizerDelegate, CPDFPageViewDelegate, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate>

@property(readwrite, nonatomic, strong) UIPageViewController *pageViewController;
@property(readwrite, nonatomic, strong) IBOutlet CContentScrollView *scrollView;
@property(readwrite, nonatomic, strong) IBOutlet UICollectionView *previewCollectionView;
@property(readwrite, nonatomic, assign) BOOL chromeHidden;
@property(readwrite, nonatomic, strong) NSCache *renderedPageCache;
@property(readwrite, nonatomic, strong) UIImage *pagePlaceholderImage;
@property(readonly, nonatomic, strong) NSArray *pages;

- (void)hideChrome;

- (void)toggleChrome;

- (BOOL)canDoubleSpreadForOrientation:(UIInterfaceOrientation)inOrientation;

- (void)resizePageViewControllerForOrientation:(UIInterfaceOrientation)inOrientation;

- (CPDFPageViewController *)pageViewControllerWithPage:(CPDFPage *)inPage;
@end

@implementation CPDFDocumentViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
    {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) != NULL)
    {
        _document.delegate = self;
        _renderedPageCache = [[NSCache alloc] init];
        _renderedPageCache.countLimit = 8;
        _statusBarHidden = YES;
    }
    return(self);
}

#pragma mark -

- (void)setDocumentURL:(NSURL *)documentURL {
    _documentURL = documentURL;
    CPDFDocument *theDocument = [[CPDFDocument alloc] initWithURL:documentURL];
    self.document = theDocument;
    theDocument.delegate = self;
}


- (void)setBackgroundView:(UIView *)backgroundView {
    if (_backgroundView != backgroundView) {
        [_backgroundView removeFromSuperview];

        _backgroundView = backgroundView;
        [self.view insertSubview:_backgroundView atIndex:0];
    }
}

- (void)setDocumentTitle:(NSString *)documentTitle {
    self.title = documentTitle;
}

#pragma mark -

- (UIInterfaceOrientation)currentInterfaceOrientation {
    return [[UIApplication sharedApplication] statusBarOrientation];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupPageViewController];
    [self setupScrollView];

    [self setupPreviewCollectionView];

    self.previewCollectionView.dataSource = self;
    self.previewCollectionView.delegate = self;

    [self registerGestureRecognizer];
}

- (void)setupPageViewController {
    UIPageViewControllerSpineLocation theSpineLocation;
    if ([self canDoubleSpreadForOrientation:self.currentInterfaceOrientation]) {
        theSpineLocation = UIPageViewControllerSpineLocationMid;
    } else {
        theSpineLocation = UIPageViewControllerSpineLocationMin;
    }

    NSDictionary *theOptions = @{UIPageViewControllerOptionSpineLocationKey: @(theSpineLocation)};

    self.pageViewController = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStylePageCurl navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal options:theOptions];
    self.pageViewController.delegate = self;
    self.pageViewController.dataSource = self;

    NSRange theRange = {.location = 1, .length = 1};
    if (self.pageViewController.spineLocation == UIPageViewControllerSpineLocationMid) {
        theRange = (NSRange) {.location = 0, .length = 2};
    }
    NSArray *theViewControllers = [self pageViewControllersForRange:theRange];
    [self.pageViewController setViewControllers:theViewControllers direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:NULL];

    [self addChildViewController:self.pageViewController];
}

- (void)setupScrollView {
    self.scrollView = [[CContentScrollView alloc] initWithFrame:self.pageViewController.view.bounds];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.contentView = self.pageViewController.view;
    self.scrollView.maximumZoomScale = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone ? 8.0f : 4.0f;
    self.scrollView.delegate = self;
    [self.scrollView addSubview:self.scrollView.contentView];
    self.scrollView.scrollEnabled = NO;
    [self.view insertSubview:self.scrollView atIndex:0];

    self.scrollView.contentInset = UIEdgeInsetsMake(-64, 0, 0, 0);

    NSDictionary *theViews = @{
            @"scrollView": self.scrollView,
    };

    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[scrollView]-0-|" options:0 metrics:NULL views:theViews]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[scrollView]-0-|" options:0 metrics:NULL views:theViews]];
}

- (void)registerGestureRecognizer {
    UITapGestureRecognizer *theSingleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
    [self.view addGestureRecognizer:theSingleTapGestureRecognizer];

    UITapGestureRecognizer *theDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    theDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:theDoubleTapGestureRecognizer];

    [theSingleTapGestureRecognizer requireGestureRecognizerToFail:theDoubleTapGestureRecognizer];
}

- (void)setStatusBadHidden:(BOOL)hidden {
    _statusBarHidden = hidden;
}

- (BOOL)prefersStatusBarHidden {
    return _statusBarHidden;
}

- (void)setupPreviewCollectionView {
    // layout
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.itemSize = CGSizeMake(95, 134);

    //collection view
    _previewCollectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 824, 768, 140) collectionViewLayout:layout];
    self.previewCollectionView.backgroundColor = UIColor.whiteColor;
    [self.previewCollectionView registerClass:[CPreviewCollectionViewCell class] forCellWithReuseIdentifier:@"CELL"];
    [self.view addSubview:_previewCollectionView];

    self.previewCollectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addConstraints:@[

            [NSLayoutConstraint constraintWithItem:self.previewCollectionView
                                         attribute:NSLayoutAttributeLeft
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:self.view
                                         attribute:NSLayoutAttributeLeft
                                        multiplier:1.0
                                          constant:0],


            [NSLayoutConstraint constraintWithItem:self.previewCollectionView
                                         attribute:NSLayoutAttributeRight
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:self.view
                                         attribute:NSLayoutAttributeRight
                                        multiplier:1.0
                                          constant:0],

            [NSLayoutConstraint constraintWithItem:self.previewCollectionView
                                         attribute:NSLayoutAttributeBottom
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:self.view
                                         attribute:NSLayoutAttributeBottom
                                        multiplier:1.0
                                          constant:0],


            [NSLayoutConstraint constraintWithItem:self.previewCollectionView
                                         attribute:NSLayoutAttributeHeight
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:nil
                                         attribute:NSLayoutAttributeNotAnAttribute
                                        multiplier:1.0
                                          constant:140.0]


    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    //
    [self resizePageViewControllerForOrientation:self.currentInterfaceOrientation];

    double delayInSeconds = 1.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
        [self populateCache];
        [self.document startGeneratingThumbnails];

        // select first cell. Both things are required to get the correct behaviour.
        UICollectionViewCell *cell = [self.previewCollectionView cellForItemAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        [cell setSelected:YES];
        [self.previewCollectionView selectItemAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] animated:NO scrollPosition:nil];
    });
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self performSelector:@selector(hideChrome) withObject:NULL afterDelay:0.5];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return (YES);
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [self resizePageViewControllerForOrientation:toInterfaceOrientation];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self.renderedPageCache removeAllObjects];
    [self populateCache];
}

- (void)hideChrome {
    if (!self.chromeHidden) {
        [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
            self.navigationController.navigationBar.alpha = 0.0;
            self.previewCollectionView.alpha = 0.0;
        }                completion:^(BOOL finished) {
            self.chromeHidden = YES;
        }];
    }
}

- (void)toggleChrome {
    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
        CGFloat newAlpha = 1.0f - (self.chromeHidden ? 0.0f : 1.0f);
        self.navigationController.navigationBar.alpha = newAlpha;
        self.previewCollectionView.alpha = newAlpha;
    }                completion:^(BOOL finished) {
        self.chromeHidden = !self.chromeHidden;
    }];
}

- (void)resizePageViewControllerForOrientation:(UIInterfaceOrientation)inOrientation {
    CGRect theBounds = self.view.bounds;
    CGRect theFrame;
    CGRect theMediaBox = [self.document pageForPageNumber:1].mediaBox;
    if ([self canDoubleSpreadForOrientation:inOrientation]) {
        theMediaBox.size.width *= 2;
        theFrame = ScaleAndAlignRectToRect(theMediaBox, theBounds, ImageScaling_Proportionally, ImageAlignment_Center);
    } else {
        theFrame = ScaleAndAlignRectToRect(theMediaBox, theBounds, ImageScaling_Proportionally, ImageAlignment_Center);
    }

    theFrame = CGRectIntegral(theFrame);

    self.pageViewController.view.frame = theFrame;
}

#pragma mark -

- (NSArray *)pageViewControllersForRange:(NSRange)inRange {
    NSMutableArray *thePages = [NSMutableArray array];
    for (NSUInteger N = inRange.location; N != inRange.location + inRange.length; ++N) {
        //thealch3m1st: if you do this on the last page of a document with an even number of pages it causes the assertion to fail because the last document is not a valid document (number of pages + 1)
        NSUInteger pageNumber = N > self.document.numberOfPages ? 0 : N;
        CPDFPage *thePage = pageNumber > 0 ? [self.document pageForPageNumber:pageNumber] : NULL;
        [thePages addObject:[self pageViewControllerWithPage:thePage]];
    }
    return (thePages);
}

- (BOOL)canDoubleSpreadForOrientation:(UIInterfaceOrientation)inOrientation {
    return !(UIInterfaceOrientationIsPortrait(inOrientation) || self.document.numberOfPages == 1);
}

- (CPDFPageViewController *)pageViewControllerWithPage:(CPDFPage *)inPage {
    CPDFPageViewController *thePageViewController = [[CPDFPageViewController alloc] initWithPage:inPage];
    thePageViewController.pagePlaceholderImage = self.pagePlaceholderImage;
    // Force load the view.
    [thePageViewController view];
    thePageViewController.pageView.delegate = self;
    thePageViewController.pageView.renderedPageCache = self.renderedPageCache;
    return (thePageViewController);
}

- (NSArray *)pages {
    return ([self.pageViewController.viewControllers valueForKey:@"page"]);
}

#pragma mark -

- (BOOL)openPage:(CPDFPage *)inPage {
    CPDFPageViewController *theCurrentPageViewController = (self.pageViewController.viewControllers)[0];
    CPDFPageViewController *rightViewPageController = self.pageViewController.viewControllers.count > 1 ? (self.pageViewController.viewControllers)[1] : nil;
    if (inPage.pageNumber == theCurrentPageViewController.page.pageNumber) {
        return (YES);
    }

    if (rightViewPageController != nil && inPage.pageNumber == rightViewPageController.page.pageNumber && self.pageViewController.doubleSided) {
        return (YES);
    }

    NSRange theRange = {.location = inPage.pageNumber, .length = 1};
    if (self.pageViewController.spineLocation == UIPageViewControllerSpineLocationMid) {
        theRange.length = 2;
    }
    NSArray *theViewControllers = [self pageViewControllersForRange:theRange];

    UIPageViewControllerNavigationDirection theDirection = inPage.pageNumber > theCurrentPageViewController.pageNumber ? UIPageViewControllerNavigationDirectionForward : UIPageViewControllerNavigationDirectionReverse;

    [self.pageViewController setViewControllers:theViewControllers direction:theDirection animated:YES completion:NULL];

    [self populateCache];

    return (YES);
}

- (void)tap:(UITapGestureRecognizer *)inRecognizer {
    [self toggleChrome];
}

- (void)doubleTap:(UITapGestureRecognizer *)inRecognizer {
    if (self.scrollView.zoomScale != 1.0) {
        [self.scrollView setZoomScale:1.0 animated:YES];
    } else {
        [self.scrollView setZoomScale:[UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone ? 2.6f : 1.66f animated:YES];
    }
}

- (void)populateCache {
    CPDFPage *theStartPage = (self.pages)[0] != [NSNull null] ? (self.pages)[0] : NULL;
    CPDFPage *theLastPage = [self.pages lastObject] != [NSNull null] ? [self.pages lastObject] : NULL;

    NSInteger theStartPageNumber = [theStartPage pageNumber];
    NSInteger theLastPageNumber = [theLastPage pageNumber];

    NSInteger pageSpanToLoad = 1;
    if (UIInterfaceOrientationIsLandscape(self.currentInterfaceOrientation)) {
        pageSpanToLoad = 2;
    }

    theStartPageNumber = MAX(theStartPageNumber - pageSpanToLoad, 0);
    theLastPageNumber = MIN(theLastPageNumber + pageSpanToLoad, self.document.numberOfPages);

    UIView *thePageView = [(CPDFPageViewController *) (self.pageViewController.viewControllers)[0] pageView];
    if (thePageView == NULL) {
        NSLog(@"WARNING: No page view.");
        return;
    }
    CGRect theBounds = thePageView.bounds;

    for (NSInteger thePageNumber = theStartPageNumber; thePageNumber <= theLastPageNumber; ++thePageNumber) {
        NSString *theKey = [NSString stringWithFormat:@"%d[%d,%d]", thePageNumber, (int) theBounds.size.width, (int) theBounds.size.height];
        if ([self.renderedPageCache objectForKey:theKey] == NULL) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                UIImage *theImage = [[self.document pageForPageNumber:thePageNumber] imageWithSize:theBounds.size scale:[UIScreen mainScreen].scale];
                if (theImage != NULL) {
                    [self.renderedPageCache setObject:theImage forKey:theKey];
                }
            });
        }
    }
}

#pragma mark -

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController {
    CPDFPageViewController *theViewController = (CPDFPageViewController *) viewController;

    NSInteger theNextPageNumber = theViewController.page.pageNumber - 1;
    if (theNextPageNumber > self.document.numberOfPages) {
        return (NULL);
    }

    if (theNextPageNumber == 0 && UIInterfaceOrientationIsPortrait(self.currentInterfaceOrientation)) {
        return (NULL);
    }

    CPDFPage *thePage = theNextPageNumber > 0 ? [self.document pageForPageNumber:theNextPageNumber] : NULL;
    theViewController = [self pageViewControllerWithPage:thePage];

    return (theViewController);
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController {
    CPDFPageViewController *theViewController = (CPDFPageViewController *) viewController;

    NSUInteger theNextPageNumber = (NSUInteger) (theViewController.page.pageNumber + 1);
    if (theNextPageNumber > self.document.numberOfPages || theViewController.page.pageNumber == 0)
        {
        //thealch3m1st: if we are in two page mode and the document has an even number of pages if it would just return NULL it woudln't flip to that last page so we have to return a an empty page for the (number of pages + 1)th page.
        if (self.document.numberOfPages % 2 == 0 &&
                theNextPageNumber == self.document.numberOfPages + 1 &&
                self.pageViewController.spineLocation == UIPageViewControllerSpineLocationMid)
            return [self pageViewControllerWithPage:NULL];
        return (NULL);
    }

    CPDFPage *thePage = theNextPageNumber > 0 ? [self.document pageForPageNumber:theNextPageNumber] : NULL;
    theViewController = [self pageViewControllerWithPage:thePage];

    return (theViewController);
}

#pragma mark -

- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray *)previousViewControllers transitionCompleted:(BOOL)completed; {
    [self populateCache];
    [self hideChrome];

    CPDFPageViewController *theFirstViewController = (self.pageViewController.viewControllers)[0];
    if (theFirstViewController.page) {
        NSArray *thePageNumbers = [self.pageViewController.viewControllers valueForKey:@"pageNumber"];
        NSMutableIndexSet *theIndexSet = [NSMutableIndexSet indexSet];
        for (NSNumber *thePageNumber in thePageNumbers) {
            NSUInteger N = (NSUInteger) ([thePageNumber integerValue] - 1);
            if (N != 0) {
                [theIndexSet addIndex:N];
            }
        }
        [theIndexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            [self.previewCollectionView selectItemAtIndexPath:[NSIndexPath indexPathForItem:idx inSection:0] animated:NO scrollPosition:UICollectionViewScrollPositionCenteredHorizontally];
        }];
    }
}

- (UIPageViewControllerSpineLocation)pageViewController:(UIPageViewController *)pageViewController spineLocationForInterfaceOrientation:(UIInterfaceOrientation)orientation {
    UIPageViewControllerSpineLocation theSpineLocation;
    NSArray *theViewControllers = NULL;

    if (UIInterfaceOrientationIsPortrait(orientation) || self.document.numberOfPages == 1) {
        theSpineLocation = UIPageViewControllerSpineLocationMin;
        self.pageViewController.doubleSided = NO;

        CPDFPageViewController *theCurrentViewController = (self.pageViewController.viewControllers)[0];
        if (theCurrentViewController.page == NULL) {
            theViewControllers = [self pageViewControllersForRange:(NSRange) {1, 1}];
        } else {
            theViewControllers = [self pageViewControllersForRange:(NSRange) {theCurrentViewController.page.pageNumber, 1}];
        }
    } else {
        theSpineLocation = UIPageViewControllerSpineLocationMid;
        self.pageViewController.doubleSided = YES;

        CPDFPageViewController *theCurrentViewController = (self.pageViewController.viewControllers)[0];
        NSUInteger theCurrentPageNumber = theCurrentViewController.page.pageNumber;

        theCurrentPageNumber = theCurrentPageNumber / 2 * 2;

        theViewControllers = [self pageViewControllersForRange:(NSRange) {theCurrentPageNumber, 2}];
    }

    [self.pageViewController setViewControllers:theViewControllers direction:UIPageViewControllerNavigationDirectionForward animated:YES completion:NULL];
    return (theSpineLocation);
}

#pragma mark -

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section; {
    return (self.document.numberOfPages);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath; {
    CPreviewCollectionViewCell *theCell = [collectionView dequeueReusableCellWithReuseIdentifier:@"CELL" forIndexPath:indexPath];

    // try to find a cached thumbnail
    UIImage *theImage = [self.document pageForPageNumber:indexPath.item + 1].thumbnail;

    // if none available we show a placeholder
    if (!theImage) {
        theImage = [UIImage imageNamed:@"Placeholder.png"];
    }

    theCell.imageView.image = theImage;
    return (theCell);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    CPDFPage *thePage;
    if(self.pageViewController.doubleSided) {
      thePage = indexPath.item % 2 == 0 ? [self.document pageForPageNumber:indexPath.item] : [self.document pageForPageNumber:indexPath.item + 1];
   }
    else {
       thePage = [self.document pageForPageNumber:indexPath.item + 1];
   }

    [self openPage:thePage];
}

#pragma mark -

- (void)PDFDocument:(CPDFDocument *)inDocument didUpdateThumbnailForPage:(CPDFPage *)inPage {
    [self.previewCollectionView reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:inPage.pageNumber - 1 inSection:0]]];
}

#pragma mark -

- (BOOL)PDFPageView:(CPDFPageView *)inPageView openPage:(CPDFPage *)inPage fromRect:(CGRect)inFrame {
    [self openPage:inPage];
    return (YES);
}

#pragma mark -

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView;     // return a view that will be scaled. if delegate returns nil, nothing happens
{
    return (self.pageViewController.view);
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
    for (UIGestureRecognizer *recognizer in self.pageViewController.gestureRecognizers) {
        recognizer.enabled = NO;
    }

    self.scrollView.scrollEnabled = YES;
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
    if (scale == 1.0) {
        for (UIGestureRecognizer *recognizer in self.pageViewController.gestureRecognizers) {
            recognizer.enabled = YES;
        }
        self.scrollView.scrollEnabled = NO;
    }
}


@end
