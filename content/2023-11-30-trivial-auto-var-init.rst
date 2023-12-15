Trivial Auto Var Init Experiments
#################################

:date: 2023-11-30
:category: mozilla
:lang: en
:authors: serge-sans-paille
:summary: exploring the impact of ``-ftrivial-auto-var-init`` on Firefox codebase

``-ftrivial-auto-var-init=[pattern|zero|uninitialized]`` is a compiler flag that controls how the stack is initialized before any value is initialized to it. The default is ``uninitialized``: no initialization is done, reading from an uninitialized location of the stack yields whatever value lies there at that point. This is Undefined Behavior in both C and C++. It makes stack allocation a :math:`\mathcal{O}(1)` operation, which is nice, but it also is (a) a common source of programming errors (b) a potential security issue.

As a countermeasure, the modes ``pattern`` and ``zero`` have been introduced.
The former sets stack slots to hard-coded patterns, depending on the type
(integral, floating point, pointer…) of the associated stack-allocated
variables, the latter justs sets the stack to zero. Both operation make stack
allocation a  :math:`\mathcal{O}(n)` operation. The idea between the two modes is that
setting stack slots to zero is faster, but setting them to a pattern is more
likely to exhibit failing behavior.


Comparing the Approach with Address Sanitizer
=============================================

Let's consider a very simple program that reads data from ``stdin`` and dumps it to
``stdout``, using a small buffer.

.. code-block:: c

    #include <stdio.h>

    int main() {
      char buffer[2048];
      size_t n;
      do {
        n = fread(buffer, 1, sizeof(buffer), stdin);
        fwrite(buffer, 1, n , stdout);
      } while(n);
      return 0;
    }


When compiled with ``clang -O2 -S -emit-llvm -o-`` the function entry block,
expressed in LLVM IR, is:

.. code-block:: llvm

    %1 = alloca [2048 x i8], align 16
    call void @llvm.lifetime.start.p0(i64 2048, ptr nonnull %1) #3
    br label %2

The first instruction allocates memory on the stack, and that's it.

If we compile it with ``clang -O2 -S -emit-llvm -o- -ftrivial-auto-var-init=zero``, the prologue becomes (note the extra ``llvm.memset`` to zero):

.. code-block:: llvm

    %1 = alloca [2048 x i8], align 16
    call void @llvm.lifetime.start.p0(i64 2048, ptr nonnull %1) #4
    call void @llvm.memset.p0.i64(ptr noundef nonnull align 16 dereferenceable(2048) %1, i8 0, i64 2048, i1 false), !annotation !3
    br label %2

When passing ``-ftrivial-auto-var-init=pattern`` we keep the ``llvm.memset``,
but zero has been turned into a pattern (``0xAA``):

.. code-block:: llvm

    %1 = alloca [2048 x i8], align 16
    call void @llvm.lifetime.start.p0(i64 2048, ptr nonnull %1) #4
    call void @llvm.memset.p0.i64(ptr noundef nonnull align 16 dereferenceable(2048) %1, i8 -86, i64 2048, i1 false), !annotation !3
    br label %2

In both cases, the ``llvm.memset`` call is annotated with some metadata that
help tracking its origin.

.. code-block:: llvm

   !3 = !{!"auto-init"}

The call to ``llvm.memset`` is directly followed by a call to ``fread`` that may
only partially write the buffer, so there is no way for the compiler to get rid
of it, even if the subsequent ``fwrite`` will never access uninitialized slots.

An important point is that on that particular code,
``-ftrivial-auto-var-init=zero/default`` doesn't have any other impact on the
code. In particular no memory read or write is being instrumented.

On the opposite, using ``-fsanitize=memory`` leads to the following function
prologue, that contains both a ``memset`` of the whole buffer and the *xoring* of
every loaded address with 87960930222080 (actually ``0x500000000000``). So it's
strictly slower, especially as it impacts elements of the inner loop (whenever
``stdout`` and ``stdin`` are loaded in memory.

.. code-block:: llvm

      %buffer = alloca [2048 x i8], align 16
      call void @llvm.lifetime.start.p0(i64 2048, ptr nonnull %buffer) #5
      %0 = ptrtoint ptr %buffer to i64
      %1 = xor i64 %0, 87960930222080
      %2 = inttoptr i64 %1 to ptr
      call void @llvm.memset.p0.i64(ptr noundef nonnull align 16 dereferenceable(2048) %2, i8 -1, i64 2048, i1 false)
      %_msld = load i64, ptr inttoptr (i64 xor (i64 ptrtoint (ptr @stdin to i64), i64 87960930222080) to ptr), align 8
      %_mscmp17.not = icmp eq i64 %_msld, 0
      br i1 %_mscmp17.not, label %4, label %3, !prof !3
    3:
      call void @__msan_warning_noreturn() #6
      unreachable
    4:
      %5 = load ptr, ptr @stdin, align 8, !tbaa !4
      %call6 = call noundef i64 @fread(ptr noundef nonnull %buffer, i64 noundef 1, i64 noundef 2048, ptr noundef %5)
      %cmp7 = icmp eq i64 %call6, 2048
      br i1 %cmp7, label %while.body, label %while.end


Compiler Optimization
---------------------

The astute reader would have noticed that in the original C code, there were two
stack variables: ``buffer`` and ``n``. Looking at the output of clang without
optimization, we can see both being allocated **and** initialized in the
function prologue

.. code-block:: llvm

    %1 = alloca i32, align 4
    %2 = alloca [2048 x i8], align 16
    %3 = alloca i64, align 8
    store i32 0, ptr %1, align 4
    call void @llvm.memset.p0.i64(ptr align 16 %2, i8 -86, i64 2048, i1 false), !annotation !4
    store i64 -6148914691236517206, ptr %3, align 8, !annotation !4
    br label %4

The ``store`` is being optimized out by the compiler (thanks to a following
``write``) to save the result of ``fread``. That's great news! It means that the
front-end compiler (here Clang) can generate initialization for every stack
variable, and let the optimizer (here LLVM) get rid of the redundant initialization.



Lowering
--------

When generating assembly code from the LLVM IR, the compiler faces a lot
choices, one of which being «should I turn a call to ``llvm.memset`` into a
block of instructions, or into a call to libc's ``memset``?». For large buffer
it chooses the latter, but were the buffer smaller, a bunch of ``mov`` (or
``movaps``, you get the idea) would be generated instead.



Evaluating Using ``-ftrivial-auto-var-init=xxxx`` on Firefox
============================================================

As a security-improving flag, ``-ftrivial-auto-var-init=xxxx`` has been
considered as a default flag to build Firefox. But as noted above, it (may) have
an impact on runtime performance. In here, we will focus on the impact on
shippable Firefox Linux when running the `Speedometer3 benchmark
<https://github.com/WebKit/Speedometer>`_.

Following table summarizes the result we get with the three setups, on three
different desktop targets (actual details are available
`for the pattern setting <https://treeherder.mozilla.org/perfherder/compare?originalProject=try&originalRevision=72364426229394f8b7818f4e690af89c7004989e&newProject=try&newRevision=7c8edf2bf86ee0df8fa7107dd937d5de5f0f823b&page=1&framework=13>`_
and
`for the zero setting <https://treeherder.mozilla.org/perfherder/compare?originalProject=try&originalRevision=72364426229394f8b7818f4e690af89c7004989e&newProject=try&newRevision=73a082680aeccbe3f7d5bf7a12c62f522e794254&page=1&framework=13>`_.

.. list-table:: Speedometer3 results dependeing on `-ftrivial-auto-var-init`   setting
    :header-rows: 1

    * - platform
      - default
      - pattern
      - zero
    * - linux64
      - 8.97
      - 8.82
      - 8.87
    * - osx10-64
      - 12.05
      - 11.95
      - 12.01
    * - win10-64
      - 12.64
      - 12.46
      - 12.47


A 1% regression on performance is not a trade off we are ready to make anytime
soon. Can we do better?

Spotting the culprit
--------------------

LLVM has a reporting mechanism that helps tracking down the behavior of the
optimizer. In particular, it can report any instruction that ends up with an
``!{!"auto-init"}`` annotation at the end of the optimization pipeline, using
the ``-Rpass-missed=annotation-remarks`` flag. On our toy example from the first
section, we get:

.. code-block:: sh

   $ clang cat.c -O2 -S -o- -ftrivial-auto-var-init=zero -Rpass-missed=annotation-remarks
   cat.c:4:8: remark: Call to memset inserted by -ftrivial-auto-var-init. Memory operation size: 2048 bytes.
    Written Variables: <unknown> (2048 bytes). [-Rpass-missed=annotation-remarks]

That's pretty nice to spot inserted instructions that end up not being
optimized, but as one can expect from a codebase as large as Firefox's, it
generates too much information.

Fortunately we can combine this with profile information, through
``-fdiagnostics-hotness-threshold=auto``, to sort out the most impactful
insertion, and analyze the result.

So the methodology becomes:

1. Compile Firefox with ``-ftrivial-auto-var-init=zero`` and ``-fprofile-generate``.
2. Train Firefox on Speedometer3 to gather profile information.
3. Recompile Firefox with ``-ftrivial-auto-var-init=zero``, ``-fprofile-use``,
   ``-Rpass-missed=annotation-remarks`` and ``-fdiagnostics-hotness-threshold=auto``, logging the result.
4. Do something smart (?) with the result.

Applied to our toy program, this summarizes into:

.. code-block:: sh

   $ clang cat.c -O2 -o cat.generate -ftrivial-auto-var-init=zero -fprofile-generate
   $ ./cat.generate < cat.c
   $ llvm-profdata merge *.profraw -o merged.profdata
   $ clang cat.c -O2 -o cat.generate -ftrivial-auto-var-init=zero -fprofile-use=merged.profdata -Rpass-missed=annotation-remarks -fdiagnostics-hotness-threshold=auto
   cat.c:4:8: remark: Call to memset inserted by -ftrivial-auto-var-init. Memory operation size: 2048 bytes.
    Written Variables: <unknown> (2048 bytes). (hotness: 1) [-Rpass-missed=annotation-remarks]
        4 |   char buffer[2048];
          |        ^

When applying the above to Firefox, we spotted a few recurring situation I'm
going to cover in the following section.


Recurring Nightmare
===================

*Bonus point if you get the reference to the MTG emblematic card.*

SmallVector and Friends
-----------------------

It is a common optimization to provide data types that preallocates some memory,
aiming at stack allocation, and switching to heap allocation depending on the
usage. In the LLVM codebase those are ``SmallVector``, ``SmallString``, ``SmallPtrSet`` etc. Similar performance-oriented data structures can be found in the Firefox codebase in the form of ``nsAutoCString`` or ``AutoTArray``. These data types provide an interesting challenge wrt. trivial auto var init: they typically are performance oriented data structure whose buffer is *not* going to be used right away. It is very unlikely that the compiler can optimize out the initialization of this buffer! Consider the following:

.. code-block:: c++

   // copy a C string into a nsAutoCStringN
   nsAutoCStringN<128> line(buffer.c_str());

Depending on the *runtime* size of ``buffer``, the pre-allocated buffer of
``line`` is going to be either partially filled, totally filled or unused in
favor of stack allocation. Only in the second case is it valid to get rid of the
full initialization... And there is no way the compiler could handle that
statically.

In some cases it is possible to avoid using these data structures (see `Bug
1850948 <https://bugzilla.mozilla.org/show_bug.cgi?id=1850948>`_)


Initialization within a Loop
----------------------------

It is quite common to declare stack variables to the stricter scope needed. It
improves locality (from a code review point of view) and it avoids exposing
variable content to other code portion. However, the interaction with
``-ftrivial-auto-var-init`` is not negligible. Consider the following code that
reads info from ``/proc/self/maps``:

.. code-block:: c

   while (std::getline(maps, line)) {
     [...]
     char modulePath[PATH_MAX + 1] = "";
     ret = sscanf(line.c_str(),
                    "%lx-%lx %6s %lx %*s %*x %" PATH_MAX_STRING(PATH_MAX)
                    "s\n",
                    &start, &end, perm, &offset, modulePath);
     [...]
   }

``-ftrivial-auto-var-init`` has the (expected!) effect of adding a ``memset`` inside
the loop, to initialize ``modulePath``. The allocation itself is going to be moved
in the function prologue, but not the initialisation. This turns a
:math:`\mathcal{O}(1)` instruction into a :math:`\mathcal{O}(n \times m)` one, where :math:`n` is
the size of the buffer and :math:`m` is the number of loop iteration. Not ideal.

The trivial (but manual) fix here is to rewrite the code as follow:

.. code-block:: c

   char modulePath[PATH_MAX + 1];
   while (std::getline(maps, line)) {
     [...]
     modulePath[0] = 0;
     ret = sscanf(line.c_str(),
                    "%lx-%lx %6s %lx %*s %*x %" PATH_MAX_STRING(PATH_MAX)
                    "s\n",
                    &start, &end, perm, &offset, modulePath);
     [...]
   }

This is not strictly equivalent though: if the loop is never entered, we still
pay for one initialisation, and the :math:`k^\text{th}` iteration can *see* the
content of previous iteration's buffer. We applied a similar patch for `Bug
1850951 <https://bugzilla.mozilla.org/show_bug.cgi?id=1850951>`_


Empty Class
-----------

Every object that may have its address taken must have a size of at least one
byte. Even if it doesn't have any members. That would be the case of the
following class:

.. code-block:: c++

   #include <cstdio>
   struct Holder {
       Holder() { puts("enter"); }
       ~Holder() { puts("exit"); }
       void log() const;
   };
   void foo() {
       Holder h;
       h.log();
   }

Now let's imagine the compiler doesn't have access to ``Holder::log()``
implementation. Or maybe it has access to it but it cannot inline it. Because it
is a member function, it takes an (implicit) reference to ``this`` as first
parameter. So the address of the object is taken. So its size becomes one, and
``-ftrivial-auto-var-init`` makes sure this padding byte is
initialized. After all, that's stack memory! Here is the LLVM bitcode output by
the compiler from the above snippet after ``clang++ -S -emit-llvm -O2
-ftrivial-auto-var-init=pattern -o- a.cpp -fno-exceptions`` (passing
``-fno-exceptions`` just to avoid the extra clutter). We can see the extra
``store i8 -86, ptr %1, align 1, !annotation !3`` that's not wanted, and the
``ptr noundef nonnull align 1 dereferenceable(1) %1`` as first parameter of
``call void @_ZNK6Holder3logEv``, i.e. ``void @Holder::log() const``.

.. code-block:: llvm

    define dso_local void @_Z3foov() local_unnamed_addr #0 {
      %1 = alloca %struct.Holder, align 1
      call void @llvm.lifetime.start.p0(i64 1, ptr nonnull %1) #4
      store i8 -86, ptr %1, align 1, !annotation !3
      %2 = tail call i32 @puts(ptr noundef nonnull dereferenceable(1) @.str)
      call void @_ZNK6Holder3logEv(ptr noundef nonnull align 1 dereferenceable(1) %1) #4
      %3 = call i32 @puts(ptr noundef nonnull dereferenceable(1) @.str.1)
      call void @llvm.lifetime.end.p0(i64 1, ptr nonnull %1) #4
      ret void
    }

Can we help the compiler there? Actually we can, by informing it that ``Holder::log`` doesn't need any reference to ``this``, while preventing it to be called without object attached:

.. code-block:: c++

   #include <cstdio>
   struct Holder {
       Holder() { puts("enter"); }
       ~Holder() { puts("exit"); }
       void log() const { return log_impl(); }
       private:
       static void log_impl();
   };
   void foo() {
       Holder h;
       h.log();
   }

gets compiled into the expected:

.. code-block:: llvm

    define dso_local void @_Z3foov() local_unnamed_addr #0 {
      %1 = tail call i32 @puts(ptr noundef nonnull dereferenceable(1) @.str)
      tail call void @_ZN6Holder8log_implEv() #3
      %2 = tail call i32 @puts(ptr noundef nonnull dereferenceable(1) @.str.1)
      ret void

This approach has been used in `Bug 1844520
<https://bugzilla.mozilla.org/show_bug.cgi?id=1844520>`_.

Manual Check
------------

At some point in the process, I decided to flag the top 100 variables reported
as initialized and hot with the attribute ``__attribute__((uninitialized))``,
which has the effect of preventing any extra initialization code to be inserted
by ``-ftrivial-auto-var-init``. I was very hopeful with that approach, as I
was expecting this attribute to significantly decrease the impact of auto-initialization on performance.
Unfortunately the opposite happened:
almost no speed improvement. This tells us that the performance impact is not
due to a few hotspot but spread across the whole codebase. So the whole idea of
handling every situation one after the other is unlikely to be enough! How
depressing.

Let's still have a look at a final situation.

Value Semantic
--------------

Maybe as an inheritance of C, maybe as an inheritance of C++98, we often see
interfaces that use pass-by-reference as a way to return extra values. For
instance in the following code ``doStuff`` returns ``false`` in case of error,
and ``true`` and sets ``result`` in case of success.

.. code-block:: c++

   #include <cstdio>
   bool doStuff(char*& result);
   void foo() {
     char* res;
     if(doStuff(res))
       puts(res);
   }

From the compiler point of view, there is no guarantee that ``res`` has been
initialized with ``doStuff``. And doing so would mean being able to couple value
and control-flow, something compilers are not always very good at.

I've asked myself how we could *inform* the compiler about this behavior. It
turns out LLVM does have attribute to specify interaction of parameters wrt.
memory, through ``memory(...)``. For instance, according to the `language
reference <https://llvm.org/docs/LangRef.html>`_ one can use ``memory(argmem:
read, inaccessiblemem: write)`` to specify that

    May only read argument memory and only write inaccessible memory.

But there is no way to state that the function **must** write to the location.
And even with that piece of information, we would have to state the write is
only done if the return value is ``true``.

One option though would be to return an ``std::optional``. In that case the
problem of initializing the return value is deferred to ``std::optional``. In
turn ``std::optional`` needs to initialize its inner members, so we're only
moving the problem.

This is, however, quite close to the situation we had with data structures that
preallocate memory: no normal usage of the data structure should lead to an
access of the uninitialized memory, and those data structures are critical
enough to trade security for performance. What about flagging them with a
specific attribute that would bypass the trivial initialization mechanism? I
actually `submitted a patch <https://reviews.llvm.org/D156337>`_ to implement
that, only to realize that the right approach would be to allow setting the
attribute on class members, which turns out to be trickier than expected. But if
we could do this, we would impact the whole codebase by only adding a few
attributes, which is much more rewarding than mechanically tracking hotspots.

Concluding Words
----------------

Firefox is probably not going to move to ``-ftrivial-auto-var-init`` anytime
soon. How disappointing.

But let's be positive! In the process of trying to decrease the performance impact
of ``-ftrivial-auto-var-init`` on Firefox codebase, I grabbed a better understanding
of the original problem and how clang approaches it. I also came up with a methodology
to track the performance impact and iteratively improve the situation. And I
shared that knowledge with you, and there is value in it, isn't there?


Acknowledgments
***************

The author would like to thank Frederik Braun and Tom Ritter for the proofreading of this post
and the fruitful discussion we've been having on that topic.
