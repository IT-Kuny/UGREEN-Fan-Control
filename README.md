# UGREEN-Fan-Control

After multiple searches I found a bunch of posts about loud fans but not how to control the fans.
This applies to those who do not use UGOS PRO but __unRAID, Debian, Ubuntu, Fedora__ etc.

Now it is possible to control the fans of a UGREEN NAS ! :)

Here is a step by step guide on how to do this:

## Package Requirements

- gcc
- make
- dkms
- dwarves
- kernel-headers / kernel-devel
- lm_sensors
- git

## System requirements to set up fan control

- SSH Client
- Basic knowledge with Linux and terminal commands

## Install Guide

### Automated Installation (Recommended)

The install script handles DKMS registration, module auto-loading at boot,
and `fancontrol` service ordering so that fan control survives reboots.

1) SSH into your UGREEN NAS

2) Install the required packages

```bash
# Fedora
sudo dnf install gcc make dkms dwarves kernel-headers kernel-devel lm_sensors git

# Debian / Ubuntu
sudo apt install gcc make dkms dwarves linux-headers-$(uname -r) lm-sensors git
```

3) Clone and run the installer

```bash
git clone --recurse-submodules https://github.com/0n1cOn3/UGREEN-Fan-Control.git
cd UGREEN-Fan-Control
sudo ./install.sh
```

4) Configure lm_sensors and fan channels

```bash
sudo sensors-detect   # answer Y to all questions
sudo pwmconfig        # creates /etc/fancontrol
```

5) Enable the fancontrol service at boot

```bash
systemctl enable --now fancontrol
```

> [!NOTE]
> The install script already configures the it87 module to load at every boot
> (`/etc/modules-load.d/it87.conf`) and adds a systemd drop-in so that
> `fancontrol.service` waits for the module to be loaded before starting.
> This prevents the race condition that previously caused the service to fail
> after a reboot.

### Manual Installation

If you prefer to install manually, follow the steps below.

1) SSH into your UGREEN NAS

2) Install the required packages (see list above)

3) Clone the repository and initialise the submodule

```bash
git clone --recurse-submodules https://github.com/0n1cOn3/UGREEN-Fan-Control.git
cd UGREEN-Fan-Control
```

4) Build and install the it87 module **via DKMS**

```bash
cd it87
sudo make dkms
```

> [!IMPORTANT]
> Use `make dkms` instead of `make && make install`. The DKMS target
> properly registers the module so it is rebuilt automatically after kernel
> updates and persists across reboots.

> [!NOTE]
> If you see:
> __Skipping BTF generation [module name] due to unavailability of vmlinux.__
>
> Run:
>
> ```bash
> sudo cp /sys/kernel/btf/vmlinux /usr/lib/modules/$(uname -r)/build/
> ```
>
> Then retry:
>
> ```bash
> make clean
> sudo make dkms
> ```

5) Configure the module to load at boot

```bash
echo "it87" | sudo tee /etc/modules-load.d/it87.conf
```

6) Create a systemd drop-in for fancontrol to wait for hardware

```bash
sudo mkdir -p /etc/systemd/system/fancontrol.service.d
sudo tee /etc/systemd/system/fancontrol.service.d/10-wait-for-hwmon.conf <<'EOF'
[Unit]
After=systemd-modules-load.service
Wants=systemd-modules-load.service

[Service]
ExecStartPre=/bin/sleep 3
Restart=on-failure
RestartSec=5
EOF
sudo systemctl daemon-reload
```

7) Configure lm_sensors and fan channels

```bash
sudo sensors-detect   # answer Y to all questions
sudo pwmconfig        # creates /etc/fancontrol
```

> [!NOTE]
> If you have previously run sensors-detect before the module was installed,
> you may see:
>
> ```txt
> Found `ITE IT8613E Super IO Sensors'                        Success!
> (address 0xa30, driver `to-be-written')
> ```
>
> This is normal. The interface to the fan controller is now available once
> the it87 module is loaded.

8) Enable the fancontrol service at boot

```bash
systemctl enable --now fancontrol
```

### Why did i that?

The idea for this project has been brought by this [Reddit post](https://www.reddit.com/r/unRAID/comments/1dzep0s/how_to_configure_fan_control_ugreen_nas/)

### Who wrote the dkms module?

That was written by 
 *  Copyright (C) 2001 Chris Gauthron
 *  Copyright (C) 2005-2010 Jean Delvare <jdelvare@suse.de>
and archived by [a1wong](https://github.com/a1wong/it87)

## Results

Tested with

```txt
# sensors-detect version 3.6.0
# System: UGREEN DXP2800 [EM_DXP2800_V1.0.25]
# Board: Default string Default string
# OS: Fedora 42 Server Edition
# Kernel: 6.14.5-300.fc42.x86_64 x86_64
# Processor: Intel(R) N100 (6/190/0)
```

```bash
root@lainpool:/# fancontrol
Loading configuration from /etc/fancontrol ...

Common settings:
  INTERVAL=10

Settings for hwmon2/pwm3:
  Depends on hwmon1/temp3_input
  Controls hwmon2/fan3_input
  MINTEMP=22
  MAXTEMP=60
  MINSTART=105
  MINSTOP=26
  MINPWM=24
  MAXPWM=255
  AVERAGE=1
```

```bash
sensors
it8613-isa-0a30
Adapter: ISA adapter
in0:         660.00 mV (min =  +0.00 V, max =  +2.81 V)
in1:           1.12 V  (min =  +0.00 V, max =  +2.81 V)
in2:           2.07 V  (min =  +0.00 V, max =  +2.81 V)
in4:           2.06 V  (min =  +0.00 V, max =  +2.81 V)
in5:           2.08 V  (min =  +0.00 V, max =  +2.81 V)
3VSB:          3.30 V  (min =  +0.00 V, max =  +5.61 V)
Vbat:          3.15 V  
+3.3V:         3.37 V  
fan2:           0 RPM  (min =    0 RPM)
fan3:        1726 RPM  (min =    0 RPM)
temp1:        +40.0°C  (low  = -128.0°C, high = +127.0°C)  sensor = thermistor
temp2:        +23.0°C  (low  = -128.0°C, high = +127.0°C)  sensor = thermistor
temp3:        +42.0°C  (low  = -128.0°C, high = +127.0°C)
intrusion0:  ALARM

acpitz-acpi-0
Adapter: ACPI interface
temp1:        +27.8°C  

coretemp-isa-0000
Adapter: ISA adapter
Package id 0:  +49.0°C  (high = +105.0°C, crit = +105.0°C)
Core 0:        +49.0°C  (high = +105.0°C, crit = +105.0°C)
Core 1:        +49.0°C  (high = +105.0°C, crit = +105.0°C)
Core 2:        +49.0°C  (high = +105.0°C, crit = +105.0°C)
Core 3:        +49.0°C  (high = +105.0°C, crit = +105.0°C)
```

## Troubleshooting

### fancontrol.service fails after reboot

This is typically caused by one of the following:

1. **it87 module not loaded at boot** – Verify it is configured:
   ```bash
   cat /etc/modules-load.d/it87.conf   # should contain "it87"
   lsmod | grep it87                    # should show the module
   ```

2. **fancontrol starts before hwmon devices are ready** – Ensure the
   systemd drop-in is in place:
   ```bash
   cat /etc/systemd/system/fancontrol.service.d/10-wait-for-hwmon.conf
   ```

3. **Module was not installed via DKMS** – Check DKMS status:
   ```bash
   dkms status | grep it87
   ```
   If it87 is not listed, re-run `sudo make dkms` from the `it87/` directory
   (or re-run `sudo ./install.sh`).

### hwmon numbering changed after reboot

If your `/etc/fancontrol` references `hwmon2` but after reboot the device
appears as `hwmon3`, run `sudo pwmconfig` again to regenerate the config.

# Bugs

Please report them here.
Anything related to dkms, please open a ticket at [a1wong](https://github.com/a1wong/it87) repository.
I do not maintain this part of the project.

## Donations

It took me a few hours to prepare, testing and deliver this for you. :)
I'll appreciate any contribution to the coffee fund :3

BTC: ```3EdkooEbQJurjCHScwUjPHGCCszoFh1pmM```

ETH: ```0x0dB50ef6C03c354795e306133B71A69d8F2e9cc6```
