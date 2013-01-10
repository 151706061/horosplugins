//
//  PLThumbnailView.h
//  PrintingLayout
//
//  Created by Benoit Deville on 03.09.12.
//
//

#import <Cocoa/Cocoa.h>
#import <OsiriXAPI/DCMView.h>

typedef enum shrinkTypeEnum {
    none    = 0,
    left,   //1
    right,  //2
/*    top,    //4
    bottom  //5*/
} shrinkType;

@interface PLThumbnailView : DCMView <NSDraggingDestination>
{
    BOOL isGoingToBeSelected;
    BOOL isSelected;
    BOOL isDraggingDestination;
//    BOOL realSizePrint;   //cf. Osirix Mailing list 13 déc. 2012, at 09:15, "mhoswa" <mhoswa@gmail.com>
                            // and 2 janv. 2013, at 11:58, "tumeursfoie" <tumeursfoie@yahoo.fr>
    
    shrinkType shrinking;   // side where the shrinking has been done
    NSRect originalFrame;   // in case of shrinking
    NSInteger layoutIndex;
}

@property BOOL isDraggingDestination, isGoingToBeSelected, isSelected;
@property shrinkType shrinking;
@property NSRect originalFrame;
@property NSInteger layoutIndex;

- (void)fillView:(NSInteger)gridIndex withPasteboard:(NSPasteboard*)pasteboard;
- (void)fillView:(NSInteger)gridIndex withPasteboard:(NSPasteboard*)pasteboard atIndex:(NSInteger)imageIndex;
- (void)fillView:(NSInteger)gridIndex withDCMView:(DCMView*)dcm atIndex:(NSInteger)imageIndex;
- (void)shrinkWidth:(int)marginSize onIts:(shrinkType)side;
- (void)backToOriginalSize;
- (void)clearView;
//- (void)resetView;
//- (void)rescaleView;
- (void)selectView;

@end
