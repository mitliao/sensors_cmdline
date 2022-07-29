#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>

#include <unistd.h>

// Declarations from other IOKit source code
typedef struct __IOHIDEvent* IOHIDEventRef;
typedef struct __IOHIDServiceClient* IOHIDServiceClientRef;
typedef double IOHIDFloat;

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
CFStringRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);
// end of borrowed declarations

NSDictionary* matching(int page, int usage)
{
    NSDictionary* dict = @ {
        @"PrimaryUsagePage" : [NSNumber numberWithInt:page],
        @"PrimaryUsage" : [NSNumber numberWithInt:usage],
    };
    return dict;
}

NSArray* getProductNames(NSDictionary* sensors)
{
    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)sensors);
    NSArray* matchingsrvs = (__bridge NSArray*)IOHIDEventSystemClientCopyServices(system);

    long count = [matchingsrvs count];
    NSMutableArray* array = [[NSMutableArray alloc] init];
    for (int i = 0; i < count; i++) {
        IOHIDServiceClientRef sc = (IOHIDServiceClientRef)matchingsrvs[i];
        NSString* name = (NSString*)IOHIDServiceClientCopyProperty(sc, (__bridge CFStringRef) @"Product");
        if (name) {
            [array addObject:name];
        } else {
            [array addObject:@"noname"];
        }
    }
    return array;
}

// from IOHIDFamily/IOHIDEventTypes.h
// e.g., https://opensource.apple.com/source/IOHIDFamily/IOHIDFamily-701.60.2/IOHIDFamily/IOHIDEventTypes.h.auto.html

#define IOHIDEventFieldBase(type) (type << 16)
#define kIOHIDEventTypeTemperature 15
#define kIOHIDEventTypePower 25

NSArray* getPowerValues(NSDictionary* sensors)
{
    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)sensors);
    NSArray* matchingsrvs = (NSArray*)IOHIDEventSystemClientCopyServices(system);

    long count = [matchingsrvs count];
    NSMutableArray* array = [[NSMutableArray alloc] init];
    for (int i = 0; i < count; i++) {
        IOHIDServiceClientRef sc = (IOHIDServiceClientRef)matchingsrvs[i];
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(sc, kIOHIDEventTypePower, 0, 0);

        NSNumber* value;
        double temp = 0.0;
        if (event != 0) {
            temp = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(kIOHIDEventTypePower)) / 1000.0;
        }
        value = [NSNumber numberWithDouble:temp];
        [array addObject:value];
    }
    return array;
}

NSArray* getThermalValues(NSDictionary* sensors)
{
    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)sensors);
    NSArray* matchingsrvs = (__bridge NSArray*)IOHIDEventSystemClientCopyServices(system);

    long count = [matchingsrvs count];
    NSMutableArray* array = [[NSMutableArray alloc] init];

    for (int i = 0; i < count; i++) {
        IOHIDServiceClientRef sc = (IOHIDServiceClientRef)matchingsrvs[i];
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(sc, kIOHIDEventTypeTemperature, 0, 0);

        NSNumber* value;
        double temp = 0.0;
        if (event != 0) {
            temp = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(kIOHIDEventTypeTemperature));
        }
        value = [NSNumber numberWithDouble:temp];
        [array addObject:value];
    }
    return array;
}

void dumpMaxValues(NSArray* kvs)
{
    int count = [kvs count];
    double max = 0.0;
    for (int i = 0; i < count; i++) {
        if ([[kvs[i] firstObject] rangeOfString:@"ACC"].location != NSNotFound) {
            if ([[kvs[i] lastObject] doubleValue] > max) {
                max = [[kvs[i] lastObject] doubleValue];
            }
            //printf("%lf", [[kvs[i] lastObject] doubleValue]);
        }
    }
    printf("%dC", (int)max);
}

void dumpValues(NSArray* kvs)
{
    int count = [kvs count];
    for (int i = 0; i < count; i++) {
        if (i > 0)
            printf(", ");
        printf("%lf", [[kvs[i] lastObject] doubleValue]);
    }
}

void dumpNames(NSArray* kvs, NSString* cat)
{
    int count = [kvs count];
    for (int i = 0; i < count; i++) {
        if (i > 0)
            printf(", ");
        printf("%s (%s)", [[kvs[i] firstObject] UTF8String], [cat UTF8String]);
    }
}

NSArray* sortKeyValuePairs(NSArray* keys, NSArray* values)
{

    NSMutableArray* unsorted_array = [[NSMutableArray alloc] init];
    for (int i = 0; i < [keys count]; i++) {
        [unsorted_array addObject:[[NSArray alloc] initWithObjects:keys[i], values[i], nil]];
    }

    NSArray* sortedArray = [unsorted_array sortedArrayUsingComparator:^(id obj1, id obj2) {
        return [[obj1 firstObject] compare:[obj2 firstObject]];
    }];
    return sortedArray;
}

void usage()
{
    printf("-c: show current meter values\n"
           "-v: show voltage meter values\n");
    return;
}

int main(int argc, char* argv[])
{

    bool voltage_show = false, current_show = false, temperature_show = false, temperature_show_max = true;
    int ch;

    while ((ch = getopt(argc, argv, "cv")) != -1) {
        switch (ch) {
        case 'v':
            voltage_show = true;
            temperature_show = true;
            temperature_show_max = false;
            break;
        case 'c':
            current_show = true;
            temperature_show = true;
            temperature_show_max = false;
            break;
        default:
            usage();
            exit(-1);
        }
    }
    argc -= optind;
    argv += optind;

    //  Primary Usage Page:
    //    kHIDPage_AppleVendor                        = 0xff00,
    //    kHIDPage_AppleVendorTemperatureSensor       = 0xff05,
    //    kHIDPage_AppleVendorPowerSensor             = 0xff08,
    //
    //  Primary Usage:
    //    kHIDUsage_AppleVendor_TemperatureSensor     = 0x0005,
    //    kHIDUsage_AppleVendorPowerSensor_Current    = 0x0002,
    //    kHIDUsage_AppleVendorPowerSensor_Voltage    = 0x0003,
    // See IOHIDFamily/AppleHIDUsageTables.h for more information
    // https://opensource.apple.com/source/IOHIDFamily/IOHIDFamily-701.60.2/IOHIDFamily/AppleHIDUsageTables.h.auto.html

    NSDictionary* currentSensors = matching(0xff08, 2);
    NSDictionary* voltageSensors = matching(0xff08, 3);
    NSDictionary* thermalSensors = matching(0xff00, 5);

    NSArray* currentNames = getProductNames(currentSensors);
    NSArray* voltageNames = getProductNames(voltageSensors);
    NSArray* thermalNames = getProductNames(thermalSensors);

    bool shown = (temperature_show_max) ? true : false;
    while (1) {
        NSArray* currentValues = getPowerValues(currentSensors);
        NSArray* voltageValues = getPowerValues(voltageSensors);
        NSArray* thermalValues = getThermalValues(thermalSensors);

        NSArray* sortedCurrent = sortKeyValuePairs(currentNames, currentValues);
        NSArray* sortedVoltage = sortKeyValuePairs(voltageNames, voltageValues);
        NSArray* sortedThermal = sortKeyValuePairs(thermalNames, thermalValues);

        if (shown == false) {
            if (voltage_show) {
                dumpNames(sortedVoltage, @"V");
                printf(", ");
            }
            if (current_show) {
                dumpNames(sortedCurrent, @"A");
                printf(", ");
            }
            if (temperature_show) {
                dumpNames(sortedThermal, @"°C");
            }
            printf("\n");
            shown = true;
        }
        if (voltage_show) {
            dumpValues(sortedVoltage);
            printf(", ");
        }
        if (current_show) {
            dumpValues(sortedCurrent);
            printf(", ");
        }
        if (temperature_show) {
            dumpValues(sortedThermal);
        }
        if (temperature_show_max) {
            dumpMaxValues(sortedThermal);
        }
        printf("\n");

        CFRelease(currentValues);
        CFRelease(voltageValues);
        CFRelease(thermalValues);

        // sleep 1 second
        usleep(1000000);
    }

    return 0;
}
