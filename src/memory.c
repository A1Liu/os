#include "memory.h"
#include "asm.h"
#include "bootboot.h"
#include "init.h"
#include "page_tables.h"
#include <basics.h>
#include <bitset.h>
#include <macros.h>
#include <types.h>

#define CLASS_COUNT 12
extern const u8 code_begin;
extern const u8 code_end;
extern const u8 bss_end;

typedef struct {
  MMapEnt *data;
  s64 count;
} MMap;

typedef struct memory__FreeBlock {
  struct memory__FreeBlock *next;
  struct memory__FreeBlock *prev;
  s64 class;
} FreeBlock;

typedef struct {
  s64 buddy;
  s64 bitset_index;
} BuddyInfo;

typedef struct {
  FreeBlock *freelist;
  BitSet buddies;
} ClassInfo;

typedef struct {
  const s64 size;
  const char *const suffix;
} MemSizeFormat;

static struct {
  s64 free_memory;

  // NOTE: This is used for checking correctness. Maybe its not necessary?
  BitSet usable_pages;
  BitSet free_pages;

  // NOTE: The smallest size class is 4kb.
  ClassInfo classes[CLASS_COUNT];
} MemGlobals;

Bump InitAlloc;

static void *alloc_from_entries(MMap mmap, s64 size, s64 align);

// Allocate `count` physically contiguous pages.
// Then:
//    if (exact == true), return NULL buffer.
//    if (exact == false), return the largest contiguous number of pages that
//    exist
static Buffer alloc_raw(s64 count, bool exact);

// get physical address from kernel address
u64 physical_address(const void *ptr) {
  u64 address = (u64)ptr;
  assert(address >= MEMORY__KERNEL_SPACE_BEGIN);

  return address - MEMORY__KERNEL_SPACE_BEGIN;
}

// get kernel address from physical address
u64 kernel_address(u64 address) {
  assert(address < MEMORY__KERNEL_SPACE_BEGIN);

  return address + MEMORY__KERNEL_SPACE_BEGIN;
}

void *kernel_ptr(u64 address) {
  assert(address < MEMORY__KERNEL_SPACE_BEGIN);

  return (void *)(address + MEMORY__KERNEL_SPACE_BEGIN);
}

static inline BuddyInfo buddy_info(s64 page, s64 class) {
  assert(is_aligned(page, 1 << class));
  s64 buddy = page ^ (S64(1) << class);
  s64 index = page >> (class + 1);
  return (BuddyInfo){.buddy = buddy, .bitset_index = index};
}

static inline MemSizeFormat mem_fmt(s64 size) {
  static const char *const sizename[] = {"", " Kb", " Mb", " Gb"};
  u8 class = 0;
  REPEAT(3) {
    if (size < 1024)
      break;
    class += 1;
    size /= 1024;
  }

  return (MemSizeFormat){.size = size, .suffix = sizename[class]};
}

void memory__init() {
  // Calculation described in bootboot specification
  MMap mmap = {.data = &bb.mmap, .count = (bb.size - 128) / 16};
  const MMapEnt *last_ent = &mmap.data[mmap.count - 1];
  const u64 end_address = MMapEnt_Ptr(last_ent) + MMapEnt_Size(last_ent);
  const u64 end_page = align_up(end_address, _4KB) / _4KB;

  FOR(mmap) {
    static const char *const typename[] = {"Used", "Free", "ACPI", "MMIO"};
    const char *const mtype = typename[MMapEnt_Type(it)];
    MemSizeFormat size_fmt = mem_fmt((s64)MMapEnt_Size(it));
    log_fmt("ENT: type=%f size=%f%f", mtype, size_fmt.size, size_fmt.suffix);
  }
  log();

  // sort the entries so that the free ones are first
  SLOW_SORT(mmap) {
    const bool swap =
        (MMapEnt_Type(left) != MMAP_FREE) & (MMapEnt_Type(right) == MMAP_FREE);
    if (swap)
      SWAP(left, right);
  }

  // remove weird bit stuff that BOOTBOOT does for the free entries
  FOR(mmap) {
    if (!MMapEnt_IsFree(it)) {
      mmap.count = index;
      break;
    }

    it->size = MMapEnt_Size(it);
  }

  // Hacky solution to quickly get everything into a higher-half kernel
  UNSAFE_HACKY_higher_half_init();

  log_fmt("higher-half addressing INIT COMPLETE");

  // Build basic buddy system structure
  const u64 buddy_max = align_up(end_address, _4KB << CLASS_COUNT);
  const s64 buddy_end_page = buddy_max / _4KB;

  u64 *usable_pages_data = alloc_from_entries(mmap, (end_page - 1) / 8 + 1, 8);
  MemGlobals.usable_pages = BitSet__from_raw(usable_pages_data, buddy_end_page);
  BitSet__set_all(MemGlobals.usable_pages, false);

  u64 *free_pages_data = alloc_from_entries(mmap, (end_page - 1) / 8 + 1, 8);
  MemGlobals.free_pages = BitSet__from_raw(free_pages_data, buddy_end_page);
  BitSet__set_all(MemGlobals.free_pages, false);

  FOR_PTR(MemGlobals.classes, CLASS_COUNT - 1, info, class) {
    const s64 bitset_size =
        align_up(buddy_info(buddy_end_page, class).bitset_index, 8);
    u64 *const data = alloc_from_entries(mmap, bitset_size / 8, 8);
    info->buddies = BitSet__from_raw(data, bitset_size);
    BitSet__set_all(info->buddies, false);
  }

  s64 available_memory = 0;
  FOR(mmap, entry) {
    u64 begin = align_up(entry->ptr, _4KB);
    u64 end = align_down(entry->ptr + entry->size, _4KB);
    s64 begin_page = begin / _4KB;
    s64 end_page = end / _4KB;
    s64 size = S64(max(end, begin) - begin);

    available_memory += size;

    BitSet__set_range(MemGlobals.usable_pages, begin_page, end_page, true);
    release_pages(kernel_ptr(begin), size / _4KB);
  }

  assert(available_memory == MemGlobals.free_memory);
  validate_heap();

  log_fmt("global allocator INIT_COMPLETE");

  // Build a new page table using functions that assume higher-half kernel
  PageTable4 *old = get_page_table();
  PageTable4 *new = zeroed_pages(1);
  assert(new);

  // Map higher half code
  const void *const target = kernel_ptr(0);
  bool res = map_region(new, (u64)target, target, (s64)end_page, PTE_KERNEL);
  assert(res);

  const u8 *code_ptr = &code_begin, *code_end_ptr = &code_end,
           *bss_end_ptr = &bss_end;
  const s64 code_size = S64(code_end_ptr - code_ptr),
            bss_size = S64(bss_end_ptr - code_end_ptr);

  // Map kernel code to address listed in the linker script
  res = copy_mapping(new, old, (u64)code_ptr, code_size / _4KB, PTE_KERNEL_EXE);
  assert(res);

  // Map BSS data
  res = copy_mapping(new, old, (u64)code_end_ptr, bss_size / _4KB, PTE_KERNEL);
  assert(res);

  // Map Bootboot struct, as described in linker script
  res = copy_mapping(new, old, (u64)&bb, 1, PTE_KERNEL);
  assert(res);

  // Map Environment data
  res = copy_mapping(new, old, (u64)&environment, 1, PTE_KERNEL);
  assert(res);

  // Map bootboot kernel stack
  res = copy_mapping(new, old, 0xFFFFFFFFFFFFF000, 1, PTE_KERNEL);
  assert(res);

  res = copy_mapping(new, old, (u64)&fb, align_up(bb.fb_size, _4KB) / _4KB,
                     PTE_KERNEL);
  assert(res);

  // Make sure BSS data stays up-to-date (because it includes MemGlobals)
  set_page_table(new);
  validate_heap();

  destroy_bootboot_table(old);
  validate_heap();

  // NOTE: this leaks intentionally. The GDT and IDT need to exist until
  // shutdown, at which time it does not matter whether they are freed.
  InitAlloc = Bump__new(2);

  log_fmt("memory INIT_COMPLETE");
}

static void *alloc_from_entries(MMap mmap, s64 _size, s64 _align) {
  assert(_size > 0 && _align >= 0);

  u64 align = max((u64)_align, 1);
  u64 size = align_up((u64)_size, align);

  FOR(mmap) {
    u64 aligned_ptr = align_up(it->ptr, align);
    u64 aligned_size = it->size + it->ptr - aligned_ptr;
    if (aligned_size < size)
      continue;

    it->ptr = aligned_ptr + size;
    it->size = aligned_size - size;
    return (void *)(aligned_ptr + MEMORY__KERNEL_SPACE_BEGIN);
  }

  assert(false);
}

static inline FreeBlock *find_block(FreeBlock *target) {
  FOR_PTR(MemGlobals.classes, CLASS_COUNT, info, class) {
    FreeBlock *block = info->freelist;
    while (block != NULL) {
      if (block == target)
        return block;
      block = block->next;
    }
  }

  return NULL;
}

static void *pop_freelist(s64 class) {
  assert(class < CLASS_COUNT);

  ClassInfo *info = &MemGlobals.classes[class];
  FreeBlock *block = info->freelist;

  assert(block != NULL);
  assert(block->class == class, "block had class %f in freelist of class %f",
         block->class, class);
  assert(block->prev == NULL);

  info->freelist = block->next;
  if (info->freelist != NULL)
    info->freelist->prev = NULL;

  return block;
}

static inline void remove_from_freelist(s64 page, s64 class) {
  assert(class < CLASS_COUNT);
  assert(is_aligned(page, 1 << class));

  FreeBlock *block = kernel_ptr(U64(page) * _4KB);
  assert(block->class == class);

  ClassInfo *info = &MemGlobals.classes[class];
  FreeBlock *prev = block->prev, *next = block->next;
  if (next != NULL)
    next->prev = prev;
  if (prev != NULL) {
    prev->next = next;
  } else {
    if (info->freelist != block) {
      log_fmt("in size class %f: freelist=%f and block=%f", class,
              (u64)info->freelist, (u64)block);
      s64 counter = 0;
      for (FreeBlock *i = info->freelist; i != NULL; i = i->next, counter++) {
        log_fmt("%f: block=%f", counter, (u64)i);
      }

      assert(false);
    }

    info->freelist = next;
  }
}

static inline void add_to_freelist(s64 page, s64 class) {
  assert(class < CLASS_COUNT);
  assert(is_aligned(page, 1 << class));

  FreeBlock *block = kernel_ptr(U64(page) * _4KB);
  ClassInfo *info = &MemGlobals.classes[class];

  block->class = class;
  block->prev = NULL;
  block->next = info->freelist;

  if (info->freelist != NULL)
    info->freelist->prev = block;
  info->freelist = block;
}

void validate_heap(void) {
  bool success = true;
  s64 calculated_free_memory = 0;
  for (s64 i = 0; i < CLASS_COUNT; i++) {
    s64 size = (s64)((1 << i) * _4KB);
    FreeBlock *block = MemGlobals.classes[i].freelist;
    for (; block != NULL; block = block->next) {
      if (block->class != i) {
        log_fmt("block class = %f but was in class %f", block->class, i);
        success = false;
      }

      calculated_free_memory += size;
    }
  }

  if (calculated_free_memory != MemGlobals.free_memory) {
    log_fmt("calculated was %f but free_memory was %f", calculated_free_memory,
            MemGlobals.free_memory);
    success = false;
  }

  assert(success);
}

void *zeroed_pages(s64 count) {
  void *data = alloc_raw(count, true).data;
  ensure(data) return NULL;

  memset(data, 0, count * _4KB);
  return data;
}

Buffer try_raw_pages(s64 count) { return alloc_raw(count, false); }

void *raw_pages(s64 count) { return alloc_raw(count, true).data; }

static Buffer alloc_raw(s64 count, bool exact) {
  Buffer buf = (Buffer){.data = NULL, .count = 0};
  if (count <= 0)
    return buf;

  const s64 min_class = smallest_greater_power2(count);
  s64 class = -1;
  NAMED_BREAK(found_class) {
    RANGE(min_class, CLASS_COUNT, current) {
      if (MemGlobals.classes[current].freelist) {
        class = current;
        break(found_class);
      }
    }

    // Could'nt allocate exactly the required amount
    if (exact)
      return buf;

    for (s64 it = min_class - 1; it >= 0; it--) {
      if (MemGlobals.classes[it].freelist) {
        count = 1 << it;
        class = it;
        break(found_class);
      }
    }

    // There's nothing left lol
    return buf;
  }

  const s64 size = count * _4KB;
  MemGlobals.free_memory -= size;

  buf.data = pop_freelist(class);
  buf.count = size;

  const u64 addr = physical_address(buf.data);
  const s64 begin = addr / _4KB, end = begin + count;
  assert(BitSet__get_all(MemGlobals.usable_pages, begin, end));
  assert(BitSet__get_all(MemGlobals.free_pages, begin, end));
  BitSet__set_range(MemGlobals.free_pages, begin, end, false);

  if (class != CLASS_COUNT - 1) {
    s64 index = buddy_info(begin, class).bitset_index;
    assert(BitSet__get(MemGlobals.classes[class].buddies, index));
    BitSet__set(MemGlobals.classes[class].buddies, index, false);
  }

  DECLARE_SCOPED(s64 remaining = count, page = begin)
  for (s64 i = class; remaining > 0 && i > 0; i--) {
    const s64 child_class = i - 1;
    ClassInfo *const info = &MemGlobals.classes[child_class];
    const s64 child_size = 1 << child_class;
    const s64 index = buddy_info(page, child_class).bitset_index;
    assert(!BitSet__get(info->buddies, index));

    if (remaining > child_size) {
      remaining -= child_size;
      page += child_size;
      continue;
    }

    add_to_freelist(page + child_size, child_class);
    BitSet__set(info->buddies, index, true);

    if (remaining == child_size)
      break;
  }

  return buf;
}

void release_pages(void *data, s64 count) {
  assert(data != NULL);
  const u64 addr = physical_address(data);
  assert(addr == align_down(addr, _4KB));

  const s64 begin = addr / _4KB, end = begin + count;
  assert(BitSet__get_all(MemGlobals.usable_pages, begin, end));
  assert(!BitSet__get_any(MemGlobals.free_pages, begin, end));

  RANGE(begin, end, page) {
    // TODO should probably do some math here to not have to iterate over every
    // page in data
    FOR_PTR(MemGlobals.classes, CLASS_COUNT - 1, info, class) {
      assert(is_aligned(page, 1 << class));
      const BuddyInfo buds = buddy_info(page, class);

      const bool buddy_is_free = BitSet__get(info->buddies, buds.bitset_index);
      BitSet__set(info->buddies, buds.bitset_index, !buddy_is_free);

      if (!buddy_is_free) {
        add_to_freelist(page, class);
        continue(page);
      }

      remove_from_freelist(buds.buddy, class);
      page = min(page, buds.buddy);
    }

    assert(is_aligned(page, 1 << (CLASS_COUNT - 1)));
    add_to_freelist(page, CLASS_COUNT - 1);
  }

  MemGlobals.free_memory += count * _4KB;
  BitSet__set_range(MemGlobals.free_pages, begin, end, true);
}

void unsafe_mark_memory_usability(const void *data, s64 count, bool usable) {
  assert(data != NULL);
  const u64 addr = physical_address(data);
  assert(addr == align_down(addr, _4KB));

  const s64 begin_page = addr / _4KB, end_page = begin_page + count;

  const bool any_are_free =
      BitSet__get_any(MemGlobals.free_pages, begin_page, end_page);
  assert(!any_are_free,
         "if you're marking memory usability, the marked pages can't be free");

  const s64 existing_pages =
      BitSet__get_count(MemGlobals.usable_pages, begin_page, end_page);
  BitSet__set_range(MemGlobals.usable_pages, begin_page, end_page, usable);
}
