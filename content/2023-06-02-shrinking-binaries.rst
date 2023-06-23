Shrinking a Shared Library
##########################

:date: 2023-06-02
:category: mozilla
:lang: en
:authors: Serge Guelton
:summary: What is the effect of different compiler flags on the size of a shared
          library? Let's explore!

Recently, I've submitted a `patch
<https://phabricator.services.mozilla.com/D179806>`_ that shaves ~2.5MB on one
of the core Firefox library, ``libxul.so``. The patch is remarkably simple, but
it's a good opportunity to dive into some techniques to shrink binary size.

Generic Approach
================

We'll use the `libz <https://github.com/madler/zlib>`_ library
from the official `zlib <https://zlib.net/>`_ as an example program to build. In
this series, we use revision **1.2.13**, sha1 **04f42ceca40f73e2978b50e93806c2a18c1281fc**.

The compiler used is clang **14.0.5**, the linker used is lld.

Compilation Levels
------------------

Let's start with the obvious approach and explore the effect of the various
optimization levels ``-O0``, ``-O1``, ``-Oz``, ``-O2`` and ``-O3``.

The ``size`` program *list section sizes and total size of binary files*, that's
perfectly suited to our needs. We will dive into its detailed output later.

.. code-block:: sh

    for opt in -O0 -O1 -O2 -O3 -Oz
    do
            rm -rf _build
            mkdir _build
            (cd ./_build ; LDFLAGS=-fuse-ld=lld CFLAGS=$opt CC=clang ../configure && make) 1>/dev/null
            size -A _build/libz.so | awk -v cflag=$opt '/Total/ { printf "%8s: %8d\n", cflag, $2 }'
    done

.. list-table:: Impact of optimization level on binary size for libz.so
    :header-rows: 1

    * - CFLAGS
      - size
    * - -O0
      - 141608
    * - -O1
      - 88164
    * - -O2
      - 99532
    * - -O3
      - 101644
    * - -Oz
      - 81006

Unsurprisingly ``-Oz`` yields the smaller binaries. , and ``-O0`` performs a
direct translation which uses a lot of space. Performing basic optimizations as
``-O1`` does generally lead to code shrinking because the optimized assembly is
more dense, and it looks like some of the optimization added by ``-O2`` generate
more instructions (Could be the result of *inlining* or *loop unrolling*).
``-O3`` trades even more binary size for performance (could be the result of
*function specialization* or more aggressive *inlining*).

Link Time Optimization
----------------------

Interestingly, using the various flavor of ``-flto`` also have an effect on the binary size:

.. code-block:: sh

    $ LDFLAGS=-fuse-ld=lld\ -flto=full CFLAGS=-Oz\ -flto=full CC=clang ../configure && make && size -A libz.so
    [...]
    Total                    80971

.. code-block:: sh

    $ LDFLAGS=-fuse-ld=lld\ -flto=full CFLAGS=-O2\ -flto=full CC=clang ../configure && make && size -A libz.so
    [...]
    Total                   102868

.. code-block:: sh

    $ LDFLAGS=-fuse-ld=lld\ -flto=thin CFLAGS=-Oz\ -flto=thin CC=clang ../configure && make && size -A libz.so
    [...]
    Total                    82096

.. code-block:: sh

    $ LDFLAGS=-fuse-ld=lld\ -flto=thin CFLAGS=-O2\ -flto=thin CC=clang ../configure && make && size -A libz.so
    [...]
    Total                   102464

Again, nothing surprising: having access to more information (through
``-flto=full``) gives more optimization space than ``-flto=thin`` which
(slightly) trades performance of the generated binary for memory usage of the
actual compilation process. A trade-off we do not need to make for zlib but it's
another story for big project like Firefox.

A Note on Stripping
-------------------

It's very common to compile a code with debug information:

.. code-block:: sh

    $ LDFLAGS=-fuse-ld=lld\ -flto=full CFLAGS=-Oz\ -g\ -flto=full CC=clang ../configure && make && size -A libz.so
    [...]
    .debug_loc               89689       0
    .debug_abbrev             1716       0
    .debug_info              33472       0
    .debug_ranges             3744       0
    .debug_str                5422       0
    .debug_line              29136       0
    Total                   244152

The impact of debug information on code size is significant. We can compress
them using ``dwz`` for a minor gain:

.. code-block:: sh

   $ dwz libz.so && size -A libz.so
   [...]
   .debug_loc               89689       0
   .debug_abbrev             1728       0
   .debug_info              27563       0
   .debug_ranges             3744       0
   .debug_str                5422       0
   .debug_line              29136       0
   Total                   238255


We usually do not ship debug info as part of a binary, yet we may want to keep minimal ones:

.. code-block:: sh

    $ LDFLAGS=-fuse-ld=lld\ -flto=full CFLAGS=-Oz\ -gline-tables-only\ -flto=full CC=clang ../configure && make && size -A libz.so
    [...]
    Total                   113441

The usual approach though is to separate debug information from the actual
binary (e.g. through ``objcopy --only-keep-debug``) then stripping it:

.. code-block:: sh

    $ strip libz.so && size -A libz.so
    [...]
    Total                   80755

It even removes some extra bytes (by shrinking the section
``.gnu.build.attributes``)!

Specializing the Binary
=======================

For a given scenario, we may be ok with removing some of the capability of the
binary in exchange for smaller binaries.

Removing ``.eh_frame``
----------------------

The complete result of the best setup we have (let's forget about stripping), ``CFLAGS=-Oz\ -flto=full``, is:

.. code-block:: sh

    $ size -A libz.so
    libz.so  :
    section                  size    addr
    .note.gnu.build-id         24     624
    .dynsym                  2616     648
    .gnu.version              218    3264
    .gnu.version_d            420    3484
    .gnu.version_r             48    3904
    .gnu.hash                 712    3952
    .dynstr                  1478    4664
    .rela.dyn                 768    6144
    .rela.plt                1056    6912
    .rodata                 17832    7968
    .eh_frame_hdr            1076   25800
    .eh_frame                7764   26880
    .text                   44592   38752
    .init                      27   83344
    .fini                      13   83372
    .plt                      720   83392
    .data.rel.ro              352   88208
    .fini_array                 8   88560
    .init_array                 8   88568
    .dynamic                  432   88576
    .got                       32   89008
    .data                       0   93136
    .tm_clone_table             0   93136
    .got.plt                  376   93136
    .bss                        1   93512
    .gnu.build.attributes     288       0
    .comment                  110       0
    Total                   80971

We can get rid of some bytes by removing support for stack unwinding:

.. code-block:: sh

    $ LDFLAGS=-fuse-ld=lld\ -flto=full\ -Wl,--lto-O2 CFLAGS=-Oz\ -flto=full\ -fno-unwind-tables\ -fno-exceptions\ -fno-asynchronous-unwind-tables\ -fomit-frame-pointer CC=clang ../configure && make && size -A libz.so
    [...]
    libz.so  :
    section                  size    addr
    .note.gnu.build-id         24     624
    .dynsym                  2616     648
    .gnu.version              218    3264
    .gnu.version_d            420    3484
    .gnu.version_r             48    3904
    .gnu.hash                 712    3952
    .dynstr                  1478    4664
    .rela.dyn                 768    6144
    .rela.plt                1056    6912
    .rodata                 17832    7968
    .eh_frame_hdr              12   25800
    .eh_frame                   4   25812
    .text                   44592   29920
    .init                      27   74512
    .fini                      13   74540
    .plt                      720   74560
    .data.rel.ro              352   79376
    .fini_array                 8   79728
    .init_array                 8   79736
    .dynamic                  432   79744
    .got                       32   80176
    .data                       0   84304
    .tm_clone_table             0   84304
    .got.plt                  376   84304
    .bss                        1   84680
    .gnu.build.attributes     288       0
    .comment                  110       0
    Total                   72147

We reduced the ``.eh_frame`` and ``.eh_frame_hdr`` sections at the expense of
removing support for stack unwinding. Again, it's a trade-off but one we may want
to make. Keep in mind the frame pointer and the exception frame are very helpful
to debug a core file!

Specializing for a given usage
------------------------------

Now let's compile the example code ``minigzip.c`` (it's part of zlib source code) while linking with our shared library, and examine the used symbols:

.. code-block:: sh

    $ clang ../test/minigzip.c -o minizip -L. -lz
    $ nm minizip | grep ' U '
                     U exit@GLIBC_2.2.5
                     U fclose@GLIBC_2.2.5
                     U ferror@GLIBC_2.2.5
                     U fileno@GLIBC_2.2.5
                     U fopen@GLIBC_2.2.5
                     U fprintf@GLIBC_2.2.5
                     U fread@GLIBC_2.2.5
                     U fwrite@GLIBC_2.2.5
                     U gzclose
                     U gzdopen
                     U gzerror
                     U gzopen
                     U gzread
                     U gzwrite
                     U __libc_start_main@GLIBC_2.34
                     U perror@GLIBC_2.2.5
                     U snprintf@GLIBC_2.2.5
                     U strcmp@GLIBC_2.2.5
                     U strlen@GLIBC_2.2.5
                     U strrchr@GLIBC_2.2.5
                     U unlink@GLIBC_2.2.5

In addition to symbols from the libc, it uses a few symbols from zlib.
This doesn't cover the whole zlib ABI though. Let's shrink the library just for our
usage using a version script that only references the symbols we want to use:

.. code-block:: sh

    $ cat ../zlib.map
    MYZLIB_1 {
        global:
                     gzclose;
                     gzdopen;
                     gzerror;
                     gzopen;
                     gzread;
                     gzwrite;
        local:
          *;
    };

And pass this to the linker:

.. code-block:: sh

    $ LDFLAGS=-fuse-ld=lld\ -flto=full\ -Wl,--gc-sections\ -Wl,--version-script,../zlib.map CFLAGS=-Oz\ -flto=full" -fno-unwind-tables -fno-exceptions -fno-asynchronous-unwind-tables -fomit-frame-pointer -ffunction-sections -fdata-sections"  CC=clang ../configure && make placebo && size -A libz.so
    [...]
    libz.so  :
    section                  size    addr
    .note.gnu.build-id         24     624
    .dynsym                   576     648
    .gnu.version               48    1224
    .gnu.version_d             84    1272
    .gnu.version_r             48    1356
    .gnu.hash                  60    1408
    .dynstr                   281    1468
    .rela.dyn                 528    1752
    .rela.plt                 336    2280
    .rodata                 15320    2624
    .eh_frame_hdr              12   17944
    .eh_frame                   4   17956
    .init                      27   22056
    .fini                      13   22084
    .text                   32608   22112
    .plt                      240   54720
    .data.rel.ro              272   59056
    .fini_array                 8   59328
    .init_array                 8   59336
    .dynamic                  432   59344
    .got                       32   59776
    .tm_clone_table             0   63904
    .got.plt                  136   63904
    .bss                        1   64040
    .gnu.build.attributes     288       0
    .comment                  110       0
    Total                   51496

The linker uses the visibility information to iteratively remove code
that's never referenced.


Concluding Notes
----------------

Some of the remaining sections are purely informational. For instance:

.. code-block:: sh

    $ objdump -s -j .comment libz.so

     0000 4743433a 2028474e 55292031 322e322e  GCC: (GNU) 12.2.
     0010 31203230 32323131 32312028 52656420  1 20221121 (Red 
     0020 48617420 31322e32 2e312d34 2900004c  Hat 12.2.1-4)..L
     0030 696e6b65 723a204c 4c442031 342e302e  inker: LLD 14.0.
     0040 3500636c 616e6720 76657273 696f6e20  5.clang version 
     0050 31342e30 2e352028 4665646f 72612031  14.0.5 (Fedora 1
     0060 342e302e 352d322e 66633336 2900      4.0.5-2.fc36). 

That's just some compiler version information, we can safely drop them:

.. code-block:: sh

    $ objcopy -R .comment libz.s
    $ size -A libz.so
    [...]
    Total                   51386

We could probably shave a few extra bytes, but we already came a long way ☺.

Acknowledgments
---------------

Thanks to **Sylvestre Ledru** and **Lancelot Six** for proof-reading this post.
You rock!
