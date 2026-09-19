"""Read USB/UVC descriptors without changing camera settings."""
import ctypes as C
import json
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--exposure-ms', type=float)
parser.add_argument('--auto-exposure', action='store_true')
args = parser.parse_args()

usb = C.CDLL('/opt/homebrew/lib/libusb-1.0.dylib')
class Descriptor(C.Structure):
    _fields_ = [('length', C.c_uint8), ('type', C.c_uint8), ('usb', C.c_uint16),
                ('cls', C.c_uint8), ('sub', C.c_uint8), ('proto', C.c_uint8),
                ('packet', C.c_uint8), ('vendor', C.c_uint16), ('product', C.c_uint16),
                ('version', C.c_uint16), ('manufacturer', C.c_uint8),
                ('name', C.c_uint8), ('serial', C.c_uint8), ('configs', C.c_uint8)]
usb.libusb_init.argtypes = [C.POINTER(C.c_void_p)]
usb.libusb_get_device_list.argtypes = [C.c_void_p, C.POINTER(C.POINTER(C.c_void_p))]
usb.libusb_get_device_list.restype = C.c_ssize_t
usb.libusb_get_device_descriptor.argtypes = [C.c_void_p, C.POINTER(Descriptor)]
usb.libusb_open.argtypes = [C.c_void_p, C.POINTER(C.c_void_p)]
usb.libusb_control_transfer.argtypes = [C.c_void_p, C.c_uint8, C.c_uint8, C.c_uint16, C.c_uint16, C.c_void_p, C.c_uint16, C.c_uint]
usb.libusb_close.argtypes = [C.c_void_p]
usb.libusb_free_device_list.argtypes = [C.POINTER(C.c_void_p), C.c_int]
usb.libusb_exit.argtypes = [C.c_void_p]
ctx = C.c_void_p()
assert usb.libusb_init(C.byref(ctx)) == 0
devices = C.POINTER(C.c_void_p)()
count = usb.libusb_get_device_list(ctx, C.byref(devices))
result = {'found': False}
for i in range(count):
    d = Descriptor()
    usb.libusb_get_device_descriptor(devices[i], C.byref(d))
    if (d.vendor, d.product) != (0x0c45, 0x0590):
        continue
    result = {'found': True, 'vendor': hex(d.vendor), 'product': hex(d.product)}
    h = C.c_void_p()
    result['open_result'] = usb.libusb_open(devices[i], C.byref(h))
    if result['open_result'] == 0:
        data = (C.c_ubyte * 4096)()
        n = usb.libusb_control_transfer(h, 0x80, 6, 0x0200, 0, data, 4096, 1000)
        result['descriptor_bytes'] = n
        descriptors = []
        offset = 0
        while offset + 2 <= n and data[offset] >= 2:
            length = data[offset]
            descriptors.append(bytes(data[offset:offset + length]).hex())
            offset += length
        result['descriptors'] = descriptors
        def get(unit, selector, request, length):
            buffer = (C.c_ubyte * length)()
            size = usb.libusb_control_transfer(h, 0xa1, request, selector << 8, unit << 8, buffer, length, 1000)
            return int.from_bytes(bytes(buffer), 'little') if size == length else {'error': size}
        def put(unit, selector, value, length):
            buffer = (C.c_ubyte * length).from_buffer_copy(value.to_bytes(length, 'little'))
            size = usb.libusb_control_transfer(h, 0x21, 1, selector << 8, unit << 8, buffer, length, 1000)
            if size != length:
                raise RuntimeError(f'UVC SET failed: {size}')
        result['controls'] = {}
        for name, unit, selector, length in [('auto_exposure', 1, 2, 1), ('exposure', 1, 4, 4), ('brightness', 2, 2, 2), ('gain', 2, 4, 2)]:
            result['controls'][name] = {key: get(unit, selector, request, length) for key, request in [('current', 0x81), ('minimum', 0x82), ('maximum', 0x83), ('step', 0x84), ('default', 0x87)]}
        if args.exposure_ms is not None:
            limits = result['controls']['exposure']
            low, high = limits['minimum'], limits['maximum']
            if not isinstance(low, int) or not isinstance(high, int):
                raise RuntimeError('Camera did not return valid exposure limits')
            value = max(low, min(high, round(args.exposure_ms * 10)))
            put(1, 2, 1, 1)  # UVC manual exposure mode
            put(1, 4, value, 4)  # UVC exposure units are 100 microseconds
            result['exposure_after'] = get(1, 4, 0x81, 4)
            result['mode_after'] = get(1, 2, 0x81, 1)
        if args.auto_exposure:
            default = result['controls']['auto_exposure']['default']
            if not isinstance(default, int) or default not in (2, 8):
                raise RuntimeError('No verified automatic exposure default')
            put(1, 2, default, 1)
            result['mode_after'] = get(1, 2, 0x81, 1)
        usb.libusb_close(h)
usb.libusb_free_device_list(devices, 1)
usb.libusb_exit(ctx)
print(json.dumps(result, indent=2))
