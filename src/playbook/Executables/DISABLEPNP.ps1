# Disable PnP (plug and play) devices
$devices = @(
	"AMD PSP",
	"AMD SMBus",
	"Base System Device",
	"Composite Bus Enumerator",
	"Direct memory access controller"
	"High precision event timer",
	"Intel Management Engine",
	"Intel SMBus",
	"Legacy device",
	# [DataUsage-fix] Do not disable the Kernel Debug NIC: it is a network-class
	# device and users reported that re-enabling it restores the Task Manager
	# network column. Disabling it is not worth the risk.
	# "Microsoft Kernel Debug Network Adapter",
	"Motherboard resources",
	"Numeric Data Processor",
	"PCI Data Acquisition and Signal Processing Controller",
	"PCI Encryption/Decryption Controller",
	"PCI Memory Controller",
	"PCI Simple Communications Controller",
	"PCI standard RAM Controller",
	"SM Bus Controller",
	"System CMOS/real time clock",
	"System Speaker",
	"System Timer"
)

# No errors as some devices may not have an option to be disabled
Get-PnpDevice -FriendlyName $devices -ErrorAction Ignore | Disable-PnpDevice -Confirm:$false -ErrorAction Ignore
