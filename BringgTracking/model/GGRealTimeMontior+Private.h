//
//  GGRealTimeMontior+Private.h
//  BringgTracking
//
//  Created by Matan on 6/29/15.
//  Copyright (c) 2015 Matan Poreh. All rights reserved.
//

#import "GGRealTimeMontior.h"
#import "BringgGlobals.h"
#import "GGTrackerManager.h"
#import "Reachability.h"

#import <BringgTracking/BringgTracking-Swift.h>

#define MAX_WITHOUT_REALTIME_SEC 240

@interface GGRealTimeMontior ()



@property (nonatomic, strong) NSString *developerToken;

@property (nonatomic, strong) NSMutableDictionary *orderDelegates;
@property (nonatomic, strong) NSMutableDictionary *driverDelegates;
@property (nonatomic, strong) NSMutableDictionary *waypointDelegates;
@property (nonatomic, strong) NSMutableDictionary *activeDrivers;
@property (nonatomic, strong) NSMutableDictionary *activeOrders;

@property (nonatomic, assign) BOOL doMonitoringOrders;
@property (nonatomic, assign) BOOL doMonitoringDrivers;
@property (nonatomic, assign) BOOL doMonitoringWaypoints;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) BOOL useSSL;
@property (nonatomic, assign) BOOL wasManuallyConnected;

@property (nonatomic,strong) SocketIOClient *socketIO;
@property (nonatomic, copy) CompletionBlock socketIOConnectedBlock;
@property (nonatomic, weak) id<RealTimeDelegate> realtimeDelegate;
@property (nonatomic, weak) id<GGRealTimeMonitorConnectionDelegate> realtimeConnectionDelegate;

@property (nonatomic, strong) Reachability* reachability;



+ (id)sharedInstance;

- (void)setRealTimeConnectionDelegate:(id<RealTimeDelegate>) connectionDelegate;


- (void)setDeveloperToken:(NSString *)developerToken;

- (void)connect;
- (void)disconnect;


-(void)sendConnectionError:(NSError *)error;


- (void)sendWatchOrderWithOrderUUID:(NSString *)uuid completionHandler:(SocketResponseBlock)completionHandler ;

- (void)sendWatchOrderWithOrderUUID:(NSString *)uuid shareUUID:(NSString *)shareUUID completionHandler:(SocketResponseBlock)completionHandler;

- (void)sendWatchDriverWithDriverUUID:(NSString *)uuid shareUUID:(NSString *)shareUUID completionHandler:(SocketResponseBlock)completionHandler;

- (void)sendWatchWaypointWithWaypointId:(NSNumber *)waypointId andOrderUUID:(NSString *)orderUUID completionHandler:(SocketResponseBlock)completionHandler ;

/**
 *  check if it has been too long since a socket event
 *
 *  @usage if no live monitor exists this will always return NO
 *  @return BOOL
 */
- (BOOL)isWaitingTooLongForSocketEvent;


/**
 *  checks if connection is active and that there has been a recent event
 *
 *  @return BOOL
 */
- (BOOL)isWorkingConnection;

@end
