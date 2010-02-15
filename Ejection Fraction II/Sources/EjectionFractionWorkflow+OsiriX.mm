//
//  EjectionFractionWorkflow+OsiriX
//  Ejection Fraction II
//
//  Created by Alessandro Volz on 17.11.09.
//  Copyright 2009 OsiriX Team. All rights reserved.
//

#import "EjectionFractionWorkflow+OsiriX.h"
#import "EjectionFractionAlgorithm.h"
#import "EjectionFractionPlugin.h"
#import "EjectionFractionStepsController.h"
#import "EjectionFractionResultsController.h"
#import <OsiriX Headers/Notifications.h>
#import <OsiriX Headers/ViewerController.h>
#import <OsiriX Headers/DCMView.h>
#import <OsiriX Headers/DicomSeries.h>
#import <OsiriX Headers/ROI.h>
#import <OsiriX Headers/NSDictionary+N2.h>
#import <OsiriX Headers/N2Debug.h>

NSString* EjectionFractionWorkflowExpectedROIChangedNotification = @"EjectionFractionWorkflowExpectedROIChangedNotification";
NSString* EjectionFractionWorkflowROIAssignedNotification = @"EjectionFractionWorkflowROIAssignedNotification";
NSString* EjectionFractionWorkflowROIIdInfo = @"EjectionFractionWorkflowROIIdInfo";

@interface EjectionFractionWorkflow (OsiriX_Private)

-(void)setRoi:(ROI*)roi forId:(NSString*)roiId;

@end

@implementation EjectionFractionWorkflow (OsiriX)

-(void)loadRoisFromViewer:(ViewerController*)viewer {
	for (NSArray* rois in [[viewer imageView] dcmRoiList])
		for (ROI* roi in rois)
			if ([_algorithm needsRoiWithId:[roi name] tag:[roi type]])
				[self setRoi:roi forId:[roi name]];	
}

-(void)initOsiriX {
	_rois = [[NSMutableDictionary alloc] initWithCapacity:8];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roiAdded:) name:OsirixAddROINotification object:NULL];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roiChanged:) name:OsirixROIChangeNotification object:NULL];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roiRemoved:) name:OsirixRemoveROINotification object:NULL];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dcmviewUpdateCurrentImage:) name:OsirixDCMUpdateCurrentImageNotification object:NULL];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(populateContextualMenu:) name:OsirixPopulatedContextualMenuNotification object:NULL];
	
	// by analyzing the currently visible ROIs, guess which algorithm couls be already applied
	NSUInteger algorithmsCount = [[_plugin algorithms] count];
	NSUInteger algorithmsROIsCounts[algorithmsCount];
	for (NSUInteger i = 0; i < algorithmsCount; ++i)
		algorithmsROIsCounts[i] = 0;
	for (ViewerController* viewer in [ViewerController getDisplayed2DViewers])
		for (NSArray* rois in [[viewer imageView] dcmRoiList])
			for (ROI* roi in rois)
				for (NSUInteger i = 0; i < algorithmsCount; ++i)
					if ([[[_plugin algorithms] objectAtIndex:i] needsRoiWithId:[roi name] tag:[roi type]])
						++algorithmsROIsCounts[i];
	CGFloat algorithmRatios[algorithmsCount];
	for (NSUInteger i = 0; i < algorithmsCount; ++i)
		algorithmRatios[i] = 1.*algorithmsROIsCounts[i]/[[[_plugin algorithms] objectAtIndex:i] countOfNeededRois];
	NSUInteger algorithmIndex = 0;
	for (NSUInteger i = 1; i < algorithmsCount; ++i)
		if (algorithmRatios[i] > algorithmRatios[algorithmIndex])
			algorithmIndex = i;
	
	[self setAlgorithm:[[_plugin algorithms] objectAtIndex:algorithmIndex]];
	
	// use the available ROIs for the algorithm
	for (ViewerController* viewer in [ViewerController getDisplayed2DViewers])
		[self loadRoisFromViewer:viewer];
}

-(void)dcmviewUpdateCurrentImage:(NSNotification*)notification {
	[self loadRoisFromViewer:[[[notification object] window] windowController]];
}

-(void)deallocOsiriX {
//	while ([_rois count])
//		[self setRoi:NULL forId:[[_rois allKeys] objectAtIndex:0]];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_rois release]; _rois = NULL;
}

+(NSArray*)roiTypesForType:(EjectionFractionROIType)roiType {
	switch (roiType) {
		case EjectionFractionROIArea:
			return [NSArray arrayWithObjects: [NSNumber numberWithLong:tCPolygon], [NSNumber numberWithLong:tOPolygon], [NSNumber numberWithLong:tPencil], NULL];
		case EjectionFractionROILength:
			return [NSArray arrayWithObject:[NSNumber numberWithLong:tMesure]];
		case EjectionFractionROIAreaOrLength:
			return [[self roiTypesForType:EjectionFractionROILength] arrayByAddingObjectsFromArray:[self roiTypesForType:EjectionFractionROIArea]];
		default:
			return NULL;
	}
}

-(void)setExpectedRoiId:(NSString*)roiId {
	[_expectedRoiId release];
	_expectedRoiId = [roiId	retain];
	[[NSNotificationCenter defaultCenter] postNotificationName:EjectionFractionWorkflowExpectedROIChangedNotification object:self];
}

-(short)pixIndexForRoi:(ROI*)roi {
//	DCMPix* pix = [roi pix];
	NSArray* dcmRoiList = [[roi curView] dcmRoiList];
	for (NSUInteger i = 0; i < [dcmRoiList count]; ++i)
		for (ROI* roii in [dcmRoiList objectAtIndex:i])
			if (roii == roi)
				return i;
	[NSException raise:NSGenericException format:@"Couldn't find ROI in list"];
	return -1;
}

-(void)selectOrOpenViewerForRoiWithId:(NSString*)roiId {
	ROI* roi = [self roiForId:roiId];
	
	if (roi) {
		DCMView* view = [roi curView];
		ViewerController* viewer = [[view window] windowController];
		[[view window] makeKeyAndOrderFront:self];
		[viewer setImageIndex:[self pixIndexForRoi:roi]];
		[viewer selectROI:roi deselectingOther:YES];
	} else {
		NSArray* roiTypes = [EjectionFractionWorkflow roiTypesForType:[_algorithm typeForRoiId:roiId]];
		[self setExpectedRoiId:roiId];
		for (ViewerController* viewer in [ViewerController getDisplayed2DViewers]) @try {
			[viewer setROIToolTag:[[roiTypes objectAtIndex:0] longValue]];
		} @catch (NSException* e) { // a fix since version 3.7b8++ solves this exception, but we want to be retro-compatible
		}
		ViewerController* viewer = [[NSApp makeWindowsPerform:@selector(frontmostViewerControllerFinder) inOrder:YES] windowController];
		[[viewer window] makeKeyAndOrderFront:self];
	}
}

-(ROI*)roiForId:(NSString*)roiId { 
	return [_rois objectForKey:roiId];
}

-(NSString*)idForRoi:(ROI*)roi {
	return [_rois keyForObject:roi];
}

-(NSArray*)roisForIds:(NSArray*)roiIds {
	NSMutableArray* rois = [NSMutableArray arrayWithCapacity:[roiIds count]];
	
	for (NSString* roiId in roiIds) {
		ROI* roi = [self roiForId:roiId];
		if (roi) [rois addObject:roi];
	}
	
	return [[rois copy] autorelease];
}

-(void)updateResult {
	@try {
		NSArray* roiIds = [_algorithm roiIds];
		if ([[self roisForIds:roiIds] count] < [roiIds count])
			[NSException raise:NSGenericException format:@"All needed ROIs must be defined"];
		[_steps setResult:[_algorithm compute:_rois]];
	} @catch (NSException* e) {
		[_steps setResult:0];
	}
}

-(void)roiChanged:(NSNotification*)notification {
	ROI* roi = [notification object];
	if ([self idForRoi:roi])
		[self updateResult];
}

extern float ROIColorR, ROIColorG, ROIColorB; // declared in ROI.m

-(void)setRoi:(ROI*)roi forId:(NSString*)roiId {
	ROI* prevRoi = [self roiForId:roiId];
	
	if (prevRoi) {
		if (roi == prevRoi) return;
		[prevRoi setName:NULL];
		RGBColor color = {[[NSUserDefaults standardUserDefaults] floatForKey: @"ROIColorR"], [[NSUserDefaults standardUserDefaults] floatForKey: @"ROIColorG"], [[NSUserDefaults standardUserDefaults] floatForKey: @"ROIColorB"]};
		[prevRoi setColor:color globally:NO];
	}
	
	DLog(@"Setting %@ as %@", [roi name], roiId);
	
	if (roi)
		[_rois setObject:roi forKey:roiId];
	else [_rois removeObjectForKey:roiId];
	
	[roi setName:roiId];
	[roi setNSColor:[_algorithm colorForRoiId:roiId] globally:NO];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:EjectionFractionWorkflowROIAssignedNotification object:self userInfo:[NSDictionary dictionaryWithObject:roiId forKey:EjectionFractionWorkflowROIIdInfo]];

	[self updateResult];
}

-(void)roiAdded:(NSNotification*)notification {
	ROI* roi = [[notification userInfo] objectForKey:@"ROI"];
	NSString* roiId = [self expectedRoiId];
	if ([self roiForId:roiId]) roiId = NULL;
	
	/// TODO: if !roiId, we should guess it
	if (!roiId)
		return;
	
	[self setRoi:roi forId:roiId];
}

-(void)roiRemoved:(NSNotification*)notification {
	ROI* roi = [notification object];
	NSString* roiId = [self idForRoi:roi];
	if (roiId) {
		[self setRoi:NULL forId:roiId];
		[self selectOrOpenViewerForRoiWithId:roiId];
	}
}

-(void)showDetails {
	[[EjectionFractionResultsController alloc] initWithWorkflow:self];
}

-(void)populateContextualMenu:(NSNotification*)notif {
	NSMenu* menu = [notif object];
	ROI* roi = [[notif userInfo] objectForKey:[ROI className]];
	
	if (roi) {
		NSMenu* submenu = [[NSMenu alloc] initWithTitle:@""];
		
		for (NSString* roiId in [_algorithm roiIds])
			if ([_algorithm typeForRoiId:roiId acceptsTag:[roi type]]) {
				NSMenuItem* temp = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Use as %@", roiId] action:@selector(menuAction_useAs:) keyEquivalent:@""];
				[temp setTarget:self];
				[temp setRepresentedObject:roi];
				[temp setTag:(NSInteger)roiId];
				[submenu addItem:temp];
				[temp release];
			}
		
		if ([submenu numberOfItems]) {
			NSMenuItem* itemSubmenu = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Ejection Fraction: %@", [_algorithm description]] action:NULL keyEquivalent:@""];
			[itemSubmenu setSubmenu:submenu];
			[menu addItem:itemSubmenu];
			[itemSubmenu release];
		}
		
		[submenu release];
	}
}

-(void)menuAction_useAs:(NSMenuItem*)source {
	ROI* roi = [source representedObject];
	NSString* roiId = (NSString*)[source tag];
	[[self roiForId:roiId] setName:NULL];
	[self setRoi:NULL forId:[roi name]];
	[self setRoi:roi forId:roiId];
}

-(CGFloat)computeAndOutputDiastoleVolume:(CGFloat&)diasVol systoleVolume:(CGFloat&)systVol {
	return [[self algorithm] compute:_rois diastoleVolume:diasVol systoleVolume:systVol];
}

@end

@implementation NSWindow (EjectionFractionWorkflow_OsiriX)

// used by selectOrOpenViewerForRoiWithId along with [NSApp makeWindowsPerform] to find the frontmost ViewerController
-(id)frontmostViewerControllerFinder {
	return [[self windowController] isKindOfClass:[ViewerController class]] ? self : NULL;
}

@end

