// ***************************************
// SCTLR_EL1, System Control Register (EL1), Page 2654 of
// AArch64-Reference-Manual.
// ***************************************

#define SCTLR_RESERVED (3 << 28) | (3 << 22) | (1 << 20) | (1 << 11)
#define SCTLR_EE_LITTLE_ENDIAN (0 << 25)
#define SCTLR_EOE_LITTLE_ENDIAN (0 << 24)
#define SCTLR_I_CACHE_DISABLED (0 << 12)
#define SCTLR_D_CACHE_DISABLED (0 << 2)
#define SCTLR_ALIGNMENT_CHECK_DISABLED (0 << 1)
#define SCTLR_MMU_DISABLED (0 << 0)
#define SCTLR_MMU_ENABLED (1 << 0)

#define SCTLR_VALUE_MMU_DISABLED                                               \
  (SCTLR_RESERVED | SCTLR_EE_LITTLE_ENDIAN | SCTLR_I_CACHE_DISABLED |          \
   SCTLR_D_CACHE_DISABLED | SCTLR_MMU_DISABLED)
#define SCTLR_VALUE_MMU_ENABLED                                                \
  (SCTLR_RESERVED | SCTLR_EE_LITTLE_ENDIAN | SCTLR_I_CACHE_DISABLED |          \
   SCTLR_D_CACHE_DISABLED | SCTLR_MMU_ENABLED)

// ***************************************
// HCR_EL2, Hypervisor Configuration Register (EL2), Page 2487 of
// AArch64-Reference-Manual.
// ***************************************

#define HCR_RW (1 << 31)
#define HCR_VALUE HCR_RW

// ***************************************
// SCR_EL3, Secure Configuration Register (EL3), Page 2648 of
// AArch64-Reference-Manual.
// ***************************************

#define SCR_RESERVED (3 << 4)
#define SCR_RW (1 << 10)
#define SCR_NS (1 << 0)
#define SCR_VALUE (SCR_RESERVED | SCR_RW | SCR_NS)

// ***************************************
// SPSR_EL3, Saved Program Status Register (EL3) Page 389 of
// AArch64-Reference-Manual.
// ***************************************

#define SPSR_MASK_ALL (7 << 6)
#define SPSR_EL1h (5 << 0)
#define SPSR_VALUE (SPSR_MASK_ALL | SPSR_EL1h)

// ***************************************
// CPACR_EL1,
// https://developer.arm.com/documentation/ddi0595/2020-12/AArch64-Registers/CPACR-EL1--Architectural-Feature-Access-Control-Register?lang=en#fieldset_0-21_20
// ***************************************

// Enables vector registers, so that calling into the Zig standard library
// doesn't cause a synchronous exception
#define CPACR_FPEN (3 << 20)

#define CPACR_VALUE (CPACR_FPEN)

// MMU values

#define MM_TYPE_PAGE_TABLE 0x3
#define MM_TYPE_PAGE 0x3
#define MM_TYPE_BLOCK 0x1
#define MM_ACCESS (0x1 << 10)
#define MM_ACCESS_PERMISSION (0x01 << 6)

/*
 * Memory region attributes:
 *
 *   n = AttrIndx[2:0]
 *			n	MAIR
 *   DEVICE_nGnRnE	000	00000000
 *   NORMAL_NC		001	01000100
 */
#define MT_DEVICE_nGnRnE 0x0
#define MT_NORMAL_NC 0x1
#define MT_DEVICE_nGnRnE_FLAGS 0x00
#define MT_NORMAL_NC_FLAGS 0x44
#define MAIR_VALUE                                                             \
  (MT_DEVICE_nGnRnE_FLAGS << (8 * MT_DEVICE_nGnRnE)) |                         \
      (MT_NORMAL_NC_FLAGS << (8 * MT_NORMAL_NC))

#define MMU_FLAGS (MM_TYPE_BLOCK | (MT_NORMAL_NC << 2) | MM_ACCESS)
#define MMU_DEVICE_FLAGS (MM_TYPE_BLOCK | (MT_DEVICE_nGnRnE << 2) | MM_ACCESS)
#define MMU_PTE_FLAGS                                                          \
  (MM_TYPE_PAGE | (MT_NORMAL_NC << 2) | MM_ACCESS | MM_ACCESS_PERMISSION)

#define TCR_T0SZ (64 - 48)
#define TCR_T1SZ ((64 - 48) << 16)
#define TCR_TG0_4K (0 << 14)
#define TCR_TG1_4K (2 << 30)
#define TCR_VALUE (TCR_T0SZ | TCR_T1SZ | TCR_TG0_4K | TCR_TG1_4K)
