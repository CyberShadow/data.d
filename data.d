/**
 * Wrappers for raw _data located in unmanaged memory.
 *
 * Using the Data class will only place a small object in managed memory, keeping the actual _data in unmanaged memory.
 * A proxy class (DataBlock) is used to safely allow multiple references to the same block of unmanaged memory.
 * When the DataBlock object is destroyed (either manually or by the garbage collector when there are no remaining Data references), the unmanaged memory is deallocated.
 *
 * This has the following advantage over using managed memory:
 * $(UL
 *  $(LI Faster allocation and deallocation, since memory is requested from the OS directly as whole pages)
 *  $(LI Greatly reduced chance of memory leaks due to stray pointers)
 *  $(LI Overall improved GC performance due to reduced size of managed heap)
 *  $(LI Memory is immediately returned to the OS when _data is deallocated)
 * )
 * On the other hand, using Data has the following disadvantages:
 * $(UL
 *  $(LI This module is designed to store raw _data which does not have any pointers. Storing objects containing pointers to managed memory is unsupported.)
 *  $(LI Accessing the contents of the Data object involves two levels of indirection. (This can be reduced to one level of indirection in future versions.) )
 *  $(LI Small objects may be stored inefficiently, as the module requests entire pages of memory from the OS. Considering allocating one large object and use slices (Data instances) for individual objects.)
 * )
 * Future directions (TODO):
 * $(UL
 *  $(LI Cache Data.block.contents to reduce the level of indirection to 1)
 *  $(LI Port to D2)
 *  $(LI Templatize and enforce non-aliased types only)
 * )
 *
 * Authors:
 *  Vladimir Panteleev <vladimir@thecybershadow.net>
 * License:
 *  Public Domain
 */

module data;

static import std.c.stdlib;
import std.c.string : memmove;
static import std.gc;
import std.outofmemory;
debug(Data) import std.stdio;
debug(Data) import std.string;
debug(Data) import Utils;

/**	The Data class represents a slice of a block of raw data. (The data itself is represented by a DataBlock class.)
	The Data class implements array-like operators and properties to allow comfortable usage of unmanaged memory.
**/

final class Data
{
private:
	/// Reference to the wrapper of the actual data.
	DataBlock block;
	/// Slice boundaries of the data block.
	size_t start, end;

	/// Maximum preallocation for append operations.
	enum { MAX_PREALLOC = 4*1024*1024 } // must be power of 2

	invariant
	{
		assert(block !is null || end == 0);
		if (block)
			assert(end <= block.capacity);
		assert(start <= end);
	}

public:
	/// Create new instance with a copy of the given data.
	this(void[] data)
	{
		block = new DataBlock(data.length);
		start = 0;
		end = data.length;
		contents[] = data;
	}

	/// Create new instance with a copy of the referenced data.
	Data dup()
	{
		return new Data(contents);
	}

	/// Create a new instance with given size/capacity. capacity defaults to size.
	this(size_t size = 0, size_t capacity = 0)
	{
		if (!capacity)
			capacity = size;

		assert(size <= capacity);
		if (capacity)
			block = new DataBlock(capacity);
		else
			block = null;
		start = 0;
		end = size;
	}

	/// Create new instance as a slice over an existing DataBlock.
	private this(DataBlock block, size_t start = 0, size_t end = size_t.max)
	{
		this.block = block;
		this.start = start;
		this.end = end==size_t.max ? block.capacity : end;
	}

	/// Empty the Data instance. Does not actually destroy referenced data.
	/// WARNING: Be careful with assignments! Since Data is a class (reference type), 
	/// assigning a Data to a Data will copy a reference to the DataBlock reference, 
	/// so a .clear on one reference will affect both. 
	/// To create a shallow copy, use the [] operator: a = b[];
	void clear()
	{
		block = null;
		start = end = 0;
	}

	/// Force immediate deallocation of referenced unmanaged data.
	/// WARNING: Unsafe! Use only when you know that you hold the only reference to the data.
	void deleteContents()
	{
		delete block;
		clear();
	}

	/// Create a new Data object containing a concatenation of this instance's contents and data.
	Data opCat(void[] data)
	{
		Data result = new Data(length + data.length);
		result.contents[0..this.length] = contents;
		result.contents[this.length..$] = data;
		return result;
	}

	/// ditto
	Data opCat(Data data)
	{
		return this.opCat(data.contents);
	}

	/// ditto
	Data opCat_r(void[] data)
	{
		Data result = new Data(data.length + length);
		result.contents[0..data.length] = data;
		result.contents[data.length..$] = contents;
		return result;
	}

	private static size_t getPreallocSize(size_t length)
	{
		if (length < MAX_PREALLOC)
			return nextPowerOfTwo(length);
		else
			return ((length-1) | (MAX_PREALLOC-1)) + 1;
	}

	/// Append data to the current instance, in-place if possible.
	/// Note that unlike opCat (a ~ b), opCatAssign (a ~= b) will preallocate.
	/// WARNING: Following "legacy" D behavior, this will stomp on available 
	/// memory in the same DataBlock that happens to be after this Data's end - 
	/// that is, if you append to a slice of Data, the appended data will 
	/// overwrite whatever was after the current instance's slice.
	Data opCatAssign(void[] data)
	{
		if (data.length==0)
			return this;
		if (start==0 && block && end + data.length <= block.capacity)
		{
			block.contents[end .. end + data.length] = data;
			end += data.length;
			return this;
		}
		else
		{
			// Create a new DataBlock with all the data
			size_t newLength = length + data.length;
			size_t newCapacity = getPreallocSize(newLength);
			auto newBlock = new DataBlock(newCapacity);
			newBlock.contents[0..this.length] = contents;
			newBlock.contents[this.length..newLength] = data;

			block = newBlock;
			start = 0;
			end = newLength;

			return this;
		}
	}

	/// ditto
	Data opCatAssign(Data data)
	{
		return this.opCatAssign(data.contents);
	}

	/// ditto
	Data opCatAssign(ubyte value) // hack?
	{
		return this.opCatAssign((&value)[0..1]);
	}

	/// Inserts data at pos. Will preallocate, like opCatAssign.
	Data splice(size_t pos, void[] data)
	{
		if (data.length==0)
			return this;
		// 0 | start | start+pos | end | block.capacity
		assert(pos <= length);
		if (start==0 && block && end + data.length <= block.capacity)
		{
			// overlapping array copy - use memmove
			auto splicePtr = cast(ubyte*)ptr + pos;
			memmove(splicePtr + data.length, splicePtr, length-pos);
			memmove(splicePtr, data.ptr, data.length);
			end += data.length;
			return this;
		}
		else
		{
			// Create a new DataBlock with all the data
			size_t newLength = length + data.length;
			size_t newCapacity = getPreallocSize(newLength);
			auto newBlock = new DataBlock(newCapacity);
			newBlock.contents[0..pos] = contents[0..pos];
			newBlock.contents[pos..pos+data.length] = data;
			newBlock.contents[pos+data.length..newLength] = contents[pos..$];

			block = newBlock;
			start = 0;
			end = newLength;

			return this;
		}
	}

	/// Duplicates the current instance, but does not actually copy the data.
	Data opSlice()
	{
		return new Data(block, start, end);
	}

	/// Return a new Data object representing a slice of the current object's memory. Does not actually copy the data.
	Data opSlice(size_t x, size_t y)
	{
		assert(x <= y);
		assert(y <= length);
		return new Data(block, start + x, start + y);
	}

	/**
	 * Return the actual memory referenced by this instance.
	 *
	 * This class has been designed to be "safe" for all cases when "contents" isn't accessed directly.
	 * Thus, direct access to "contents" should be avoided when possible.
	 *
	 * Notes on working with contents directly:
	 * $(UL
	 *  $(LI Concatenations (the ~ operator, not appends) will work as expected, but the result will always be allocated in managed memory (use Data classes to avoid this))
	 *  $(LI Appends ( ~= ) to contents will cause undefined behavior - you should use Data classes instead)
	 *  $(LI Be sure to keep the Data reference reachable by the GC - otherwise contents can become a dangling pointer!)
	 * )
	 */
	void[] contents()
	{
		return block ? block.contents[start..end] : null;
	}

	/// Return a pointer to the beginning of referenced data.
	void* ptr()
	{
		return contents.ptr;
	}

	/// Return the length of referenced data.
	size_t length()
	{
		return end - start;
	}
	
	/// Resize, in-place when possible.
	void length(size_t value)
	{
		if (value == length) // no change
			return;
		if (value < length) // shorten
			end = start + value;
		else
		if (start==0 && start + value <= block.capacity) // lengthen - with available space
			end = start + value;
		else // reallocate
		{
			auto newBlock = new DataBlock(value);
			newBlock.contents[0..this.length] = contents;
			//(cast(ubyte[])newBlock.contents)[this.length..value] = 0;
			
			block = newBlock;
			start = 0;
			end = value;
		}
	}
}

// ************************************************************************

import std.stream;

/// Read a file directly into a new Data block.
Data readData(string filename)
{
	/*auto contents = std.file.read(filename);
	auto data = new Data(contents);
	delete contents;*/
	
	auto size = std.file.getSize(filename);
	assert(size < uint.max);
	auto data = new Data(cast(uint)size);
	scope file = new File(filename);
	file.readExact(data.ptr, data.length);
	return data;
}

// ************************************************************************

version(DataStats)
{
	static size_t dataMemory, dataMemoryPeak;
	static uint   dataCount, allocCount;
}

private: // Implementation detail follows

version (Windows)
	import std.c.windows.windows;
else version (FreeBSD)
	import std.c.freebsd.freebsd;
else version (Solaris)
	import std.c.solaris.solaris;
else version (linux)
	import std.c.linux.linux;

/// Actual block.
final class DataBlock
{
	/// Pointer to actual data.
	final void* data;
	/// Allocated capacity.
	final size_t capacity;

	/// Threshold of allocated memory to trigger a collect.
	enum { COLLECT_THRESHOLD = 8*1024*1024 } // 8MB
	/// Counter towards the threshold.
	static size_t allocatedThreshold;

	/// Create a new instance with given capacity.
	this(size_t capacity)
	{
		data = malloc(capacity);
		if (data is null) // system is out of memory?
		{
			debug(Data) printf("Garbage collect triggered by failed Data allocation... ");
			//debug(Data) printStats();
			std.gc.fullCollect();
			//debug(Data) printStats();
			debug(Data) printf("Done\n");
			data = malloc(capacity);
			allocatedThreshold = 0;
		}
		if (data is null)
			_d_OutOfMemory();
		
		version(DataStats)
		{
			dataMemory += capacity;
			if (dataMemoryPeak < dataMemory)
				dataMemoryPeak = dataMemory;
			dataCount ++;
			allocCount ++;
		}

		this.capacity = capacity;

		// also collect
		allocatedThreshold += capacity;
		if (allocatedThreshold > COLLECT_THRESHOLD)
		{
			debug(Data) printf("Garbage collect triggered by total allocated Data exceeding threshold... ");
			std.gc.fullCollect();
			debug(Data) printf("Done\n");
			debug(Data) printStats();
			allocatedThreshold = 0;
		}
	}

	/// Destructor - destroys the wrapped data.
	~this()
	{
		free(data, capacity);
		data = null;
		// If DataBlock is created and manually deleted, there is no need to cause frequent collections
		if (allocatedThreshold > capacity)
			allocatedThreshold -= capacity;
		else
			allocatedThreshold = 0;
		
		version(DataStats)
		{
			dataMemory -= capacity;
			dataCount --;
		}
	}

	void[] contents()
	{
		return data[0..capacity];
	}

	debug(Data) static void printStats()
	{
		std.gc.GCStats stats;
		std.gc.getStats(stats);
		with(stats)
			printf("poolsize=%d, usedsize=%d, freeblocks=%d, freelistsize=%d, pageblocks=%d", poolsize, usedsize, freeblocks, freelistsize, pageblocks);
		printf(" | %d bytes in %d objects\n", dataMemory, dataCount);
	}

	version(Windows)
	{
		static size_t pageSize;

		static this()
		{
			SYSTEM_INFO si;
			GetSystemInfo(&si);
			pageSize = si.dwPageSize;
		}
	}
	else
	version(linux)
	{
		static size_t pageSize;

		static this()
		{
			version(linux) const _SC_PAGE_SIZE = 30;
			pageSize = sysconf(_SC_PAGE_SIZE);
		}
	}

	static void* malloc(ref size_t size)
	{
		if (is(typeof(pageSize)))
			size = ((size-1) | (pageSize-1))+1;

		version(Windows)
		{
			return VirtualAlloc(null, size, MEM_COMMIT, PAGE_READWRITE);
		}
		else
		version(Posix)
		{
			auto p = mmap(null, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
			return (p == MAP_FAILED) ? null : p;
		}
		else
			return std.c.malloc(size);
	}

	static void free(void* p, size_t size)
	{
		debug(DataStomp) (cast(ubyte*)p)[0..size] = 0xBA;
		version(Windows)
			return VirtualFree(p, 0, MEM_RELEASE);
		else
		version(Posix)
			return munmap(p, size);
		else
			return std.c.free(size);
	}
}

// Source: http://bits.stephan-brumme.com/roundUpToNextPowerOfTwo.html
size_t nextPowerOfTwo(size_t x)
{
	x |= x >> 1;  // handle  2 bit numbers
	x |= x >> 2;  // handle  4 bit numbers
	x |= x >> 4;  // handle  8 bit numbers
	x |= x >> 8;  // handle 16 bit numbers
	x |= x >> 16; // handle 32 bit numbers
	static if (size_t.sizeof==8)
		x |= x >> 32; // handle 64 bit numbers
	x++;

	return x;
}

// Source: Win32 bindings project
version(Windows)
{
   	struct SYSTEM_INFO {
   		union {
   			DWORD dwOemId;
   			struct {
   				WORD wProcessorArchitecture;
   				WORD wReserved;
   			}
   		}
   		DWORD dwPageSize;
   		PVOID lpMinimumApplicationAddress;
   		PVOID lpMaximumApplicationAddress;
   		DWORD dwActiveProcessorMask;
   		DWORD dwNumberOfProcessors;
   		DWORD dwProcessorType;
   		DWORD dwAllocationGranularity;
   		WORD  wProcessorLevel;
   		WORD  wProcessorRevision;
   	}
   	alias SYSTEM_INFO* LPSYSTEM_INFO;

   	extern(Windows) VOID GetSystemInfo(LPSYSTEM_INFO);
}

version(Posix)
{
	extern (C) int sysconf(int);
}
