//
//  GGRealTimeManager.m
//  BringgTracking
//
//  Created by Matan on 6/25/15.
//  Copyright (c) 2015 Matan Poreh. All rights reserved.
//

#import "GGRealTimeMontior.h"
#import "GGRealTimeMontior+Private.h"

#import "SocketIOPacket.h"


#import "GGDriver.h"
#import "GGCustomer.h"
#import "GGOrder.h"
#import "GGSharedLocation.h"
#import "GGRating.m"

//#define BRINGG_REALTIME_SERVER @"realtime.bringg.com"


#define EVENT_ORDER_UPDATE @"order update"
#define EVENT_ORDER_DONE @"order done"

#define EVENT_DRIVER_LOCATION_CHANGED @"location update"
#define EVENT_DRIVER_ACTIVITY_CHANGED @"activity change"

#define EVENT_WAY_POINT_ARRIVED @"way point arrived"
#define EVENT_WAY_POINT_DONE @"way point done"
#define EVENT_WAY_POINT_ETA_UPDATE @"way point eta updated"





@implementation GGRealTimeMontior

@synthesize realtimeDelegate;


+ (id)sharedInstance {
    DEFINE_SHARED_INSTANCE_USING_BLOCK(^{
        return [[self alloc] init];
        
    });
}

- (id)init {
    if (self = [super init]) {
        
        self.orderDelegates = [NSMutableDictionary dictionary];
        self.driverDelegates = [NSMutableDictionary dictionary];
        self.waypointDelegates = [NSMutableDictionary dictionary];
        self.activeDrivers = [NSMutableDictionary dictionary];
        self.activeOrders = [NSMutableDictionary dictionary];
        // let the real time manager handle socket events
        self.socketIO = [[SocketIO alloc] initWithDelegate:self];
     
        self.connected = NO;
        
        // start reachability monitor
        [self configureReachability];
    }
    
    return self;
    
}


- (void)configureReachability {
    Reachability* reachability = [Reachability reachabilityWithHostname:@"www.google.com"];
    self.reachability = reachability;
    reachability.reachableBlock = ^(Reachability*reach) {
        NSLog(@"Reachable!");
        if (![self.socketIO isConnected] && ![self.socketIO isConnecting] && self.developerToken) {
            [self connect];

        }
    };
    reachability.unreachableBlock = ^(Reachability*reach) {
        NSLog(@"Unreachable!");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self disconnect];
        });
        

    };
    
    [reachability startNotifier];
    
}



- (void) setRealTimeConnectionDelegate:(id<RealTimeDelegate>) connectionDelegate{
    self.realtimeDelegate = connectionDelegate;
}

-(void)sendConnectionError:(NSError *)error{
    
    self.connected = NO;
    
    if (self.realtimeDelegate && [self.realtimeDelegate respondsToSelector:@selector(trackerDidDisconnectWithError:)]) {
        [self.realtimeDelegate trackerDidDisconnectWithError:error];
    }
}

#pragma mark - Setters

-(void)useSecureConnection:(BOOL)shouldUse{
    self.useSSL = shouldUse;
}

- (void)addAndUpdateOrder:(GGOrder *)order{
    // add this order to the orders active list if needed;
    if (order != nil && order.uuid != nil) {
        
        if (![self.activeOrders objectForKey:order.uuid]) {
            [self.activeOrders setObject:order forKey:order.uuid];
        }else{
            [[self.activeOrders objectForKey:order.uuid] update:order];
        }
        
    }

}
- (void)addAndUpdateDriver:(GGDriver *)driver{
    // add this driver to the drivers active list if needed
    if (driver != nil && driver.uuid != nil) {
        
        if (![self.activeDrivers objectForKey:driver.uuid]) {
            [self.activeDrivers setObject:driver forKey:driver.uuid];
        }else{
            [[self.activeDrivers objectForKey:driver.uuid] update:driver];
        }
        
    }
}

#pragma mark - Getters

-(BOOL)hasNetwork{
    return [self.reachability isReachable];
}

-(GGOrder * _Nullable)getOrderWithUUID:(NSString * _Nonnull)uuid{
    return [self.activeOrders objectForKey:uuid];
}

-(GGDriver * _Nullable)getDriverWithUUID:(NSString * _Nonnull)uuid{
    return [self.activeDrivers objectForKey:uuid];
}

-(GGDriver * _Nullable)getDriverWithID:(NSNumber * _Nonnull)driverId{
    NSArray *allActiveDrivers = [self.activeDrivers allValues];
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"driverid==%@", driverId];
    return [[allActiveDrivers filteredArrayUsingPredicate:pred] firstObject];
}


#pragma mark - Helper

- (NSDate *)dateFromString:(NSString *)string {
    NSDate *date;
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    [dateFormat setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
    date = [dateFormat dateFromString:string];
    if (!date) {
        [dateFormat setDateFormat:@"yyyy-MM-dd HH:mm:ss Z"];
        date = [dateFormat dateFromString:string];
        
    }
    if (!date) {
        [dateFormat setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        date = [dateFormat dateFromString:string];
        
    }
    return date;
    
}


#pragma mark - SocketIO actions

- (void)webSocketConnectWithCompletionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    
    NSString *server;
    
    if (self.realtimeConnectionDelegate && [self.realtimeConnectionDelegate respondsToSelector:@selector(hostDomainForRealTimeMonitor:)]) {
        server = [self.realtimeConnectionDelegate hostDomainForRealTimeMonitor:self];
    }
    
    if (!server) {
        server = BTRealtimeServer;
    }
    
    self.socketIO.useSecure = self.useSSL;
    
    if ([self.socketIO isConnected] || [self.socketIO isConnecting]) {
       
        if (completionHandler) {
            NSError *error = [NSError errorWithDomain:@"BringgRealTime" code:0
                                             userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Already connected.", @"eng/heb")}];
            completionHandler(NO, error);
            
        }
    } else {
        
        if (!self.developerToken) {
            if (completionHandler) {
                NSError *error = [NSError errorWithDomain:@"BringgRealTime" code:0
                                                 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Invalid Developer Token", @"eng/heb")}];
                completionHandler(NO, error);
                
            }

            
            return;
        }
        
        self.socketIOConnectedBlock = completionHandler;
        
        if (self.reachability.isReachable) {
            
            NSLog(@"websocket connecting %@", server);
            
            
            [self.socketIO connectToHost:server
                                  onPort:0
                              withParams:@{@"developer_access_token":self.developerToken}];
        }
        
        
    }
}

- (void)setDeveloperToken:(NSString *)developerToken{
    _developerToken = developerToken;
}



- (void)connect {
    NSLog(@"Trying Connecting!");
    [self webSocketConnectWithCompletionHandler:^(BOOL success, NSError *error) {
        
        self.connected = success;
        NSLog(@"Connected: %d ", success);
        
        if (success) {
            [self.realtimeDelegate trackerDidConnect];
            
        } else {
            [self.realtimeDelegate trackerDidDisconnectWithError:error];
            
        }
    }];
}

- (void)disconnect {
    [self webSocketDisconnect];
    
}


- (void)webSocketDisconnect {
    NSLog(@"websocket disconnected");
    [self.socketIO disconnect];
    self.connected = NO;
    
}

- (void)sendEventWithName:(NSString *)name params:(NSDictionary *)params completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    if (!self.connected) {
        if (completionHandler) {
            NSError *error = [NSError errorWithDomain:@"BringgRealTime" code:0
                                             userInfo:@{NSLocalizedDescriptionKey: @"Web socket disconnected.",
                                                        NSLocalizedRecoverySuggestionErrorKey: @"Web socket disconnected."}];
            completionHandler(NO, error);
            
        }
        return;
        
    }
    SocketIOCallback cb;
    if (completionHandler) {
        
        cb = ^(id argsData) {
            NSLog(@"SocketIOCallback argsData %@", argsData);
            NSError *error;
            if (![self errorAck:argsData error:&error]) {
                completionHandler(YES, nil);
                
            } else {
                completionHandler(NO, error);
                
            }
        };
    }
    
    [self.socketIO sendEvent:name withData:params andAcknowledge:cb];
    
}



- (BOOL)errorAck:(id)argsData error:(NSError **)error {
    BOOL errorResult = NO;
    NSString *message;
    if ([argsData isKindOfClass:[NSString class]]) {
        NSString *data = (NSString *)argsData;
        if ([[data lowercaseString] rangeOfString:@"error"].location != NSNotFound) {
            errorResult = YES;
            message = data;
        }
        
    } else if ([argsData isKindOfClass:[NSDictionary class]]) {
        NSNumber *success = [argsData objectForKey:@"success"];
        message = [argsData objectForKey:@"message"];
        if (![success boolValue]) {
            errorResult = YES;
            
        }
    }
    if (errorResult) {
        *error = [NSError errorWithDomain:@"BringgRealTime" code:0
                                 userInfo:@{NSLocalizedDescriptionKey:message,
                                            NSLocalizedRecoverySuggestionErrorKey:message}];
        
    }
    return errorResult;
    
}


#pragma mark - SocketIO callbacks

- (void) socketIODidConnect:(SocketIO *)socket {
    NSLog(@"websocket connected");
    
    self.connected = YES;
    
    if (self.socketIOConnectedBlock) {
        
         NSLog(@"\t\thandling connect success");
        
        self.socketIOConnectedBlock(YES, nil);
        self.socketIOConnectedBlock = nil;
        
    }
    
}

- (void) socketIODidDisconnect:(SocketIO *)socket disconnectedWithError:(NSError *)error {
    NSLog(@"websocket disconnected, error %@", error);
    
    // set the real timemonitor as disconnected
    self.connected = NO;
    
    // try to execture connection blocks
    if (self.socketIOConnectedBlock) {
        self.socketIOConnectedBlock(NO, error);
        self.socketIOConnectedBlock = nil;
        
    } else {
        
        // report connection error
        [self sendConnectionError:error];
    
    }
    
    
  
}

- (void) socketIO:(SocketIO *)socket didReceiveMessage:(SocketIOPacket *)packet {
    NSLog(@"Received packet [%@]", packet.data);
    
}

- (void) socketIO:(SocketIO *)socket didReceiveJSON:(SocketIOPacket *)packet {
    NSLog(@"Received packet [%@]", packet.data);
    
}

- (void) socketIO:(SocketIO *)socket didReceiveEvent:(SocketIOPacket *)packet {
    NSLog(@"Received packet [%@]", packet.data);
    if ([packet.name isEqualToString:EVENT_ORDER_UPDATE]) {
        
        NSDictionary *eventData = [packet.args firstObject];
        
        NSString *orderUUID = [eventData objectForKey:PARAM_UUID];
        NSNumber *orderStatus = [eventData objectForKey:PARAM_STATUS];
        
        //GGOrder *order = [[GGOrder alloc] initOrderWithUUID:orderUUID atStatus:(OrderStatus)orderStatus.integerValue];
        
        GGOrder *updatedOrder = [[GGOrder alloc] initOrderWithData:eventData];
        GGDriver *updatedDriver = [eventData objectForKey:PARAM_DRIVER] ? [[GGDriver alloc] initDriverWithData:[eventData objectForKey:PARAM_DRIVER]] : nil;
        
        // updated existing model
        [self addAndUpdateOrder:updatedOrder];
        [self addAndUpdateDriver:updatedDriver];
    
        
        // get most updated model
        GGOrder *order = [self.activeOrders objectForKey:orderUUID];
        GGDriver *driver = [self.activeDrivers objectForKey:updatedDriver.uuid];
        
        //test get order method
//        NSNumber *orderID = [eventData objectForKey:PARAM_ID];
//
//         
//        [self orderWithOrderID:orderID completionHandler:^(BOOL success, NSNumber *status, NSError *error) {
//            NSLog(@"status %@, error %@", status, error);
//
//        }];
        
        id existingDelegate = [self.orderDelegates objectForKey:orderUUID];
        
        NSLog(@"delegate: %@ should update order with status:%@", existingDelegate, orderStatus );
        
        if (existingDelegate) {
            switch ([orderStatus integerValue]) {
                case OrderStatusAssigned:
                    [existingDelegate orderDidAssignWithOrder:order withDriver:driver];
                    break;
                case OrderStatusAccepted:
                    [existingDelegate orderDidAcceptWithOrder:order withDriver:driver];
                    break;
                case OrderStatusOnTheWay:
                    [existingDelegate orderDidStartWithOrder:order withDriver:driver];
                    break;
                case OrderStatusCheckedIn:
                    [existingDelegate orderDidArrive:order withDriver:driver];
                    break;
                case OrderStatusDone:
                    [existingDelegate orderDidFinish:order withDriver:driver];
                    break;
                case OrderStatusCancelled:
                case OrderStatusRejected:
                    [existingDelegate orderDidCancel:order withDriver:driver];
                    break;
                default:
                    break;
            }
            
        }
    } else if ([packet.name isEqualToString:EVENT_ORDER_DONE]) {
        NSDictionary *eventData = [packet.args firstObject];

        NSString *orderUUID = [eventData objectForKey:PARAM_UUID];
        
        GGOrder *updatedOrder = [[GGOrder alloc] initOrderWithData:eventData];
        
        if (!updatedOrder){
            updatedOrder = [self.activeOrders objectForKey:orderUUID];
        }
        
        [updatedOrder updateOrderStatus:OrderStatusDone];
        
        GGDriver *updatedDriver = [[GGDriver alloc] initDriverWithData:[eventData objectForKey:PARAM_DRIVER]];
        

        // updated existing model
        [self addAndUpdateOrder:updatedOrder];
        [self addAndUpdateDriver:updatedDriver];
        
        
        // get most updated model
        GGOrder *order = [self.activeOrders objectForKey:orderUUID];
        GGDriver *driver = [self.activeDrivers objectForKey:updatedDriver.uuid];

        
        id existingDelegate = [self.orderDelegates objectForKey:orderUUID];
        
        NSLog(@"delegate: %@ should finish order %ld(%@)", existingDelegate, (long)order.orderid, order.uuid );
        
        if (existingDelegate) {
            [existingDelegate orderDidFinish:order  withDriver:driver];
            
        }
    } else if ([packet.name isEqualToString:EVENT_DRIVER_LOCATION_CHANGED]) {
        NSDictionary *locationUpdate = [packet.args firstObject];
        NSString *driverUUID = [locationUpdate objectForKey:PARAM_DRIVER_UUID];
        NSNumber *lat = [locationUpdate objectForKey:@"lat"];
        NSNumber *lng = [locationUpdate objectForKey:@"lng"];
        
        // get driver from data
        GGDriver *driver = [self.activeDrivers objectForKey:driverUUID];
        
        // if no data get it from the current active drivers
        if (!driver) {
            driver = [self.activeDrivers objectForKey:self.activeDrivers.allKeys.firstObject];
        }
        
        if (driver) {
            [driver updateLocationToLatitude:lat.doubleValue longtitude:lng.doubleValue];
            
            id existingDelegate = [self.driverDelegates objectForKey:driver.uuid];
            
            NSLog(@"delegate: %@ should udpate location for driver :%@", existingDelegate, driver.uuid );
            
            if (existingDelegate) {
                [existingDelegate driverLocationDidChangeWithDriver:driver];
                
            }
        }
        
        
    } else if ([packet.name isEqualToString:EVENT_DRIVER_ACTIVITY_CHANGED]) {
        //activity change
        NSLog(@"driver activity changed: %@", packet.args);
        
    } else if ([packet.name isEqualToString:EVENT_WAY_POINT_ETA_UPDATE]) {
        NSDictionary *etaUpdate = [packet.args firstObject];
        NSNumber *wpid = [etaUpdate objectForKey:@"way_point_id"];
        NSString *eta = [etaUpdate objectForKey:@"eta"];
        NSDate *etaToDate = [self dateFromString:eta];
        
        id existingDelegate = [self.waypointDelegates objectForKey:wpid];
        NSLog(@"delegate: %@ should udpate waypoint %@ ETA to: %@", existingDelegate, wpid, eta );
       
        if (existingDelegate) {
            [existingDelegate waypointDidUpdatedWaypointId:wpid eta:etaToDate];
            
        }
    } else if ([packet.name isEqualToString:EVENT_WAY_POINT_ARRIVED]) {
        NSDictionary *waypointArrived = [packet.args firstObject];
        NSNumber *wpid = [waypointArrived objectForKey:@"way_point_id"];
        id existingDelegate = [self.waypointDelegates objectForKey:wpid];
        
        NSLog(@"delegate: %@ should udpate waypoint %@ arrived", existingDelegate, wpid );
        
        if (existingDelegate) {
            [existingDelegate waypointDidArrivedWaypointId:wpid];
            
        }
        
    } else if ([packet.name isEqualToString:EVENT_WAY_POINT_DONE]) {
        NSDictionary *waypointDone = [packet.args firstObject];
        NSNumber *wpid = [waypointDone objectForKey:@"way_point_id"];
        id existingDelegate = [self.waypointDelegates objectForKey:wpid];
        
         NSLog(@"delegate: %@ should udpate waypoint %@ done", existingDelegate, wpid );
        
        if (existingDelegate) {
            [existingDelegate waypointDidArrivedWaypointId:wpid];
            
        }
    }
}

- (void) socketIO:(SocketIO *)socket didSendMessage:(SocketIOPacket *)packet {
    NSLog(@"Packet sent [%@]", packet.data);
    
}

- (void) socketIO:(SocketIO *)socket onError:(NSError *)error {
    
    self.connected = [socket isConnected];
    
    NSLog(@"Send error %@", error);
    
}


- (void)sendWatchOrderWithOrderUUID:(NSString *)uuid completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    NSLog(@"watch order");
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   uuid, @"order_uuid",
                                   nil];
    [self sendEventWithName:@"watch order" params:params completionHandler:completionHandler];
    
}

- (void)sendWatchDriverWithDriverUUID:(NSString *)uuid shareUUID:(NSString *)shareUUID completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    NSLog(@"watch driver");
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   uuid, @"driver_uuid",
                                   shareUUID, @"share_uuid",
                                   nil];
    [self sendEventWithName:@"watch driver" params:params completionHandler:completionHandler];
    
}

- (void)sendWatchWaypointWithWaypointId:(NSNumber *)waypointId completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    NSLog(@"watch waypoint");
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   waypointId, @"way_point_id",
                                   nil];
    [self sendEventWithName:@"watch way point" params:params completionHandler:completionHandler];
    
}




@end
