{  
  boot = {  
    initrd = {  
      kernelModules = [ "rp1" "bcm2712-rpi-5-b" ];  
      availableKernelModules = [ "usbhid" "hid" "hid-generic" "evdev" ];  
    };  
    kernelParams = [ "ip=${config.hostConfig.initrdIp}" ];  
  };  
  networking = {  
    systemd = {  
      networks."10-ethernet" = {  
        address = config.hostConfig.lanIp;  
      };  
    };  
  };  
  # Host configuration  
  hostConfig = {  
    initrdIp = if config.hostname == "host1" then "10.13.12.249" else "10.13.12.248";  
    lanIp = if config.hostname == "host1" then "10.13.12.249" else "10.13.12.248";  
  };  
}