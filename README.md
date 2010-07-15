<h1>data</h1>
Wrappers for raw data located in unmanaged memory.

Using the Data class will only place a small object in managed memory, keeping the actual data in unmanaged memory.
 A proxy class (DataBlock) is used to safely allow multiple references to the same block of unmanaged memory.
 When the DataBlock object is destroyed (either manually or by the garbage collector when there are no remaining Data references), the unmanaged memory is deallocated.


 This has the following advantage over using managed memory:
 <ul> <li>Faster allocation and deallocation, since memory is requested from the OS directly as whole pages</li>
  <li>Greatly reduced chance of memory leaks due to stray pointers</li>
  <li>Overall improved GC performance due to reduced size of managed heap</li>
  <li>Memory is immediately returned to the OS when data in deallocated</li>
 </ul>
 On the other hand, using Data has the following disadvantages:
 <ul> <li>This module is designed to store raw data which does not have any pointers. Storing objects containing pointers to managed memory is unsupported.</li>
  <li>Accessing the contents of the Data object involves two levels of indirection. (This can be reduced to one level of indirection in future versions.) </li>
  <li>Small objects may be stored inefficiently, as the module requests entire pages of memory from the OS. Considering allocating one large object and use slices (Data instances) for individual objects.</li>
 </ul>
 Future directions (TODO):
 <ul> <li>Cache Data.block.contents to reduce the level of indirection to 1</li>
  <li>Port to D2</li>
  <li>Templatize and enforce non-aliased types only</li>
 </ul>


<b>Authors:</b><br>
Vladimir Panteleev <vladimir@thecybershadow.net>

<b>License:</b><br>
Public Domain

<dl><dt><big>class <u>Data</u>;
</big></dt>
<dd>The <u>Data</u> class represents a slice of a block of raw data. (The data itself is represented by a DataBlock class.)
	The <u>Data</u> class implements array-like operators and properties to allow comfortable usage of unmanaged memory.<br><br>

<dl><dt><big>this(void[] <i>data</i>);
</big></dt>
<dd>Create new instance with a copy of the given <i>data</i>.<br><br>

</dd>
<dt><big>Data <u>dup</u>();
</big></dt>
<dd>Create new instance with a copy of the referenced data.<br><br>

</dd>
<dt><big>this(size_t <i>size</i> = 0, size_t <i>capacity</i> = 0);
</big></dt>
<dd>Create a new instance with given <i>size</i>/<i>capacity</i>. <i>capacity</i> defaults to <i>size</i>.<br><br>

</dd>
<dt><big>void <u>clear</u>();
</big></dt>
<dd>Empty the Data instance. Does not actually destroy referenced data.
<br><br>
<b>WARNING:</b><br>
Be careful with assignments! Since Data is a class (reference type), 
 assigning a Data to a Data will copy a reference to the DataBlock reference, 
 so a .<u>clear</u> on one reference will affect both. 
 To create a shallow copy, use the [] operator: a = b[];<br><br>

</dd>
<dt><big>void <u>deleteContents</u>();
</big></dt>
<dd>Force immediate deallocation of referenced unmanaged data.
<br><br>
<b>WARNING:</b><br>
Unsafe! Use only when you know that you hold the only reference to the data.<br><br>

</dd>
<dt><big>Data <u>opCat</u>(void[] <i>data</i>);
<br>Data <u>opCat</u>(Data <i>data</i>);
<br>Data <u>opCat_r</u>(void[] <i>data</i>);
</big></dt>
<dd>Create a new Data object containing a concatenation of this instance's contents and <i>data</i>.<br><br>

</dd>
<dt><big>Data <u>opCatAssign</u>(void[] <i>data</i>);
<br>Data <u>opCatAssign</u>(Data <i>data</i>);
<br>Data <u>opCatAssign</u>(ubyte <i>value</i>);
</big></dt>
<dd>Append <i>data</i> to the current instance, in-place if possible.
 Note that unlike opCat (a ~ b), <u>opCatAssign</u> (a ~= b) will preallocate.
<br><br>
<b>WARNING:</b><br>
Following "legacy" D behavior, this will stomp on available 
 memory in the same DataBlock that happens to be after this Data's end - 
 that is, if you append to a slice of Data, the appended <i>data</i> will 
 overwrite whatever was after the current instance's slice.<br><br>

</dd>
<dt><big>Data <u>splice</u>(uint <i>pos</i>, void[] <i>data</i>);
</big></dt>
<dd>Inserts <i>data</i> at <i>pos</i>. Will preallocate, like opCatAssign.<br><br>

</dd>
<dt><big>Data <u>opSlice</u>();
</big></dt>
<dd>Duplicates the current instance, but does not actually copy the data.<br><br>

</dd>
<dt><big>Data <u>opSlice</u>(uint <i>x</i>, uint <i>y</i>);
</big></dt>
<dd>Return a new Data object representing a slice of the current object's memory. Does not actually copy the data.<br><br>

</dd>
<dt><big>void[] <u>contents</u>();
</big></dt>
<dd>Return the actual memory referenced by this instance.
<br><br>
This class has been designed to be "safe" for all cases when "<u>contents</u>" isn't accessed directly.
 Thus, direct access to "<u>contents</u>" should be avoided when possible.
<br><br>

 Notes on working with <u>contents</u> directly:
 <ul> <li>Concatenations (the ~ operator, not appends) will work as expected, but the result will always be allocated in managed memory (use Data classes to avoid this)</li>
  <li>Appends ( ~= ) to <u>contents</u> will cause undefined behavior - you should use Data classes instead</li>
  <li>Be sure to keep the Data reference reachable by the GC - otherwise <u>contents</u> can become a dangling pointer!</li>
 </ul>

</dd>
<dt><big>void* <u>ptr</u>();
</big></dt>
<dd>Return a pointer to the beginning of referenced data.<br><br>

</dd>
<dt><big>uint <u>length</u>();
</big></dt>
<dd>Return the <u>length</u> of referenced data.<br><br>

</dd>
<dt><big>void <u>length</u>(uint <i>value</i>);
</big></dt>
<dd>Resize, in-place when possible.<br><br>

</dd>
</dl>
</dd>
<dt><big>Data <u>readData</u>(char[] <i>filename</i>);
</big></dt>
<dd>Read a file directly into a new Data block.<br><br>

</dd>
</dl>

<hr><small>Page generated by <a href="http://www.digitalmars.com/d/1.0/ddoc.html">Ddoc</a>. </small>
</body></html>
