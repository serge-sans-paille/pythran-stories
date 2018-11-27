:Author: Jean Laroche <ripngo@gmail.com>

================================================================================
 Pythran as a bridge between fast prototyping and code deployment
================================================================================


Introduction
================================================================================

As a researcher/engineer (really, an algorithm developer) in the general area of audio and speech processing, I've always run into the same difficulty at all the companies I've worked at: How to quickly prototype and develop algorithms, and subsequently turn them into efficient code that can be deployed to customers. These have always been incompatible goals: For rapid prototyping, over many years, I've used Matlab, then Python with Numpy. Both are wonderful in the level of mathematical abstraction they provide (for example, 1 line to multiply a matrix by a vector), and they're very useful for testing and debugging as they're interpreted and provide a full array of plotting routines for inspecting what's going on in your algorithm. For example, you can put a breakpoint in your program, and when it stops, you can start poking around, executing high-level commands, etc. But when came time to deploy the prototype algorithm, we typically had to bite the bullet and rewrite it in C or C++: For one thing, it was not possible or practical to ship Matlab or Numpy to our customers so our prototype code could be run in their environment. It was also crucial to squeeze every drop of efficiency out of the processor, and predictability and reproducibility of performance was also very important! When processing real-time audio, you cannot wait around for garbage collection to terminate because you will run out of audio samples to play. So interpreted languages were pretty much out. This means we had teams of people porting the Matlab or Python code to C++, creating test vectors to ensure results were similar enough, and henceforth maintaining the C++ code to ensure that it still matched the Matlab/Python reference code. This was an enormous overhead, but one that was still preferable to prototyping in C/C++. In some of the companies I worked at, we tested various tools to convert Matlab to C++ but none of them were truly satisfactory (most of them required you to severely constrain the way you coded so the conversion code could run).

Then I discovered Pythran. Unlike Cython and Numba, Pythran not only accelerates your Python code (by compiling modules into fast .so files) but Pythran also generates self-contained C++ code that implements your Python/Numpy algorithm. The C++ code is fully portable, does not require any Python or Numpy libraries, does not rely at all on Python, and can easily be incorporated into a C++ project. Once compiled, you prototype code becomes extremely efficient, optimized for the target architecture, and its performance is predictable and reproducible. What's more, you do not need to change anything to your Python code to make it work with Pythran, provided that you're using supported functions and features, so you can keep your prototype code as your reference, update and improve it, and re-generate the fast C++ version with a single command. No need to maintain and synchronize two versions of the same code.
To me, this is nothing short of a revolution in how I do my work. To show you the new workflow I use, I've take an example of a moderately complicated audio algorithm written in Python. With this blog post, you'll be able to see how simple it is to convert the high-level Python/Numpy code into a fully deployable, fast, C++ version.


An example: time-scaling an audio file.
================================================================================

A note on time-scaling:
__________________________________


Time scaling in audio signal processing refers to slowing down or speeding up an audio recording while preserving its original pitch (frequency). You may be familiar with playing back a record or a tape at half its normal speed: this both slows down the music but it also changes the pitch: for example a singer's voice become completely unnatural, a female singer might start sounding more like a male. Instead of the music being in a certain key, say A major, it will play in a different key (E major for example), if speeding up by a factor 1.5x. This is undesirable and many techniques have been developed to allow controlling the playback speed while preserving the original tone of the music.
Time-scaling is useful for example if you're trying to figure out a fast series of notes in an improvisation for example, or if you're learning a language and want hear a speaker at a slower speed...

Some time-scaling technique operates in the "frequency domain", i.e. using a Fourier transform to get a view of which frequencies are present in the music at any given time. The one I chose in this blog post is a frequency domain technique that's both simple, and achieves reasonable quality for most (but definitely not all) audio tracks and is described in the paper "Improved  Phase  Vocoder
Time-Scale  Modification  of  Audio" IEEE  TRANSACTIONS  ON SPEECH  AND  AUDIO  PROCESSING, VOL.  7,  NO.  3,  MAY  1999. See for example: Paper_. If you're interested in the general area of audio time-scaling, the Wikipedia entry_ is a very good introduction.

The technique uses a Fast Fourier Transform (FFT), pick peaking to locate pure tones in the audio, and complex rotations to adjust the phase of the Fourier transom prior to reconstructing the audio signal.

Python/Numpy code:
__________________________________
The code is shown below. Refer to the paper if you're interested in the "theoretical" explanation for what's being done. As you can see, the Numpy implementation is simple but not trivial, requiring several steps. Note that the algorithm uses both real and complex numbers: the output of the rfft routine is a complex array, and the rotations are complex numbers. Copy the code below into a time_scaling.py file.

::

    import numpy as np


    def hanning(M):
        if M < 1: return np.array([])
        if M == 1: return np.ones(1, float)
        n = np.arange(0, M)
        return 0.5 - 0.5*np.cos(2.0*np.pi*n/(M-1))

    def computeRotation(X,rotations,fftSize,inputHop,outputHop):
        # Compute the appropriate rotations based on input and output hop.
        AX = np.abs(X)
        # Find peaks in AX: values that are larger than their two neighbors on the left and on the right
        peaks = 2+np.nonzero((AX[2:-2]>AX[1:-3]) & (AX[2:-2]>AX[0:-4]) & (AX[2:-2]>AX[3:-1]) & (AX[2:-2]>AX[4:]))[0]
        for ii,id in enumerate(peaks):
            # Compute new rotation.
            rot = np.exp(2*np.pi*1j*id/fftSize*(outputHop-inputHop))
            # Cumulate rotation with the one from the previous frame.
            rotations[id]*=rot
            # Now spread this rotation to all the neighboring bins (half-way between peaks).
            if ii==0: left = 0
            else: left = int(.5*(peaks[ii-1]+id))
            if ii==len(peaks)-1: right = len(AX)
            else: right = int(.5*(peaks[ii+1]+id))
            rotations[left:right]=rotations[id]
        return rotations

    def process(signal,sRate,factor = 1.):
        # Process parameters.
        windowLengthS = 0.060
        windowHopS = 0.030

        windowLength = int(np.round(windowLengthS*sRate))
        windowHop = int(np.round(windowHopS*sRate))
        fftSize = int(2**np.ceil(np.log2(windowLength)))
        window = np.sqrt(hanning(windowLength))
        halfWinLen = int(np.floor(windowLength/2))

        curInSamp = 0
        curOutSamp = 0
        prevInSamp = curInSamp-windowHop
        # Initialize rotations. They're complex, and they're the same for all channels.
        rotations = np.ones(fftSize/2+1,dtype=np.complex)
        outSig = np.zeros(int(factor*len(signal)),dtype=signal.dtype)
        xx = np.zeros(fftSize)
        while 1:
            if curInSamp+windowLength > len(signal): break
            if curOutSamp+windowLength > len(outSig): break
            # Take the fft of the signal starting at curInSamp. It's a good thing to have a zero-phase fft so roll it by
            # half a window size so the middle of the input window is at t=0
            xx[0:windowLength] = signal[curInSamp:curInSamp+windowLength] * window
            xx[windowLength:] = 0
            xx = np.roll(xx,-halfWinLen)
            X = np.fft.rfft(xx,fftSize)
            # Compute required rotations based on the input and output hop.
            computeRotation(X,rotations,fftSize,curInSamp-prevInSamp,windowHop)
            # Apply to FFT
            Y = X * rotations
            # Take the inverse FFT, undo the circular roll and overlap add into the output signal.
            yy = np.fft.irfft(Y,fftSize)
            yy = np.roll(yy,halfWinLen)
            outSig[curOutSamp:curOutSamp+windowLength] += yy[0:windowLength] * window
            # Increment the output sample by half a window size, and the input sample according to the time scaling factor.
            prevInSamp = curInSamp
            curOutSamp += windowHop
            curInSamp = int(np.round(curOutSamp/factor))

        return outSig

Now we can run the process function on an audio file. For simplicity I'm using a .wav file: Scipy has a very simple interface for reading or writing a .wav file.
Note that our process function expects a 1D input array. If you open a stereo .wav file, the array returned by wavfile.read will be 2D. In case this happens I'm only keeping the left channel. You can copy paste the following code into a main.py function:

::

    import time_scaling
    import numpy as np
    from scipy.io import wavfile

    sRate, data = wavfile.read(r'/Users/jlaroche/temp/MessageInABottleMono.wav')
    x=data[:,0] if data.ndim == 2 else data
    factor = 1.2
    out = time_scaling.process(x.astype(float)/32767,float(sRate),factor)
    wavfile.write('./out.wav',sRate,(32767*out).astype(np.int16))

You should be able to open the output file and listen to it in any program that plays wavfiles (for example afplay on macos).

Let's time the function in Ipython. For this you start Ipython (install it if you don't have it, it's a great complement to Python)).
In Ipython, you can simply put %timeit in front of the line you'd like to benchmark:

::

    %timeit out = time_scaling.process(x.astype(float)/32767,float(sRate),factor)

For the (quite long) wav file I was using, %timeit returned
::

    1 loop, best of 3: 15.1 s per loop


Using Pythran:
__________________________________


To be able to use the process function from the module that Pythran will create, we need to export it to Python. This is what the following #pythran export directive does. This can be placed anywhere in the .py file.

::

    #pythran export process(float[] or float[::],float,float)

Note that the first parameter is declared as float[] or float[::] a simple float Numpy array or a view into a float Numpy array. The two remaining parameters are declared as float and it will be crucial to pass them as floats when calling process.

Now simply run

::

    pythran time_scaling.py.

A time_scaling.so file is created.
Now the same main.py code will execute much faster because import time_scaling will now import a compiled, very efficient .so file.

For the same file as above, %timeit now returns:
::

    1 loop, best of 3: 1.87 s per loop

The speed up is amazing. The function runs about 14 times faster than it did in pure Python/Numpy.
Note that if you pass an int instead of a float to the process function time_scaling.process(x.astype(float)/32767,int(sRate),factor) you will get a run-time error so make sure you're passing the very same types you've declared in time_scaling.py.


Calling from C++
__________________________________

As I explained above, one of the most amazing aspects of Pythran is that it generates self contained C++ code that can be called from any other C++ program. As I explained, the code is self contained in that it does not require any dlls, and makes no call to the Python library. In short, it's a very efficient C++ version of your Python/Numpy algorithm, fully portable to any target architecture.
To create a c++ version of our process function, we simply do:

::

    pythran -e time_scaling.py

This creates a file time_scaling.cpp that can then be compiled along with the calling code. Note that in this case, the #pythran export declaration is no longer needed. You can take a look at the C++ code, but it will be extremely cryptic and heavily templated... But that's not a problem as this code never need to be hand-tweaked.

Now, how do we call this process() function from our main C++ program?
For this, we must pass the audio in a Numpy like array, but the Pythran C++ source code provides convenient functions to do just that.
This is the main.cpp file:

::

    #include <stdio.h>      /* printf, scanf, NULL */
    #include <stdlib.h>

    #include "numpy/_numpyconfig.h"
    #include "time_scaling.cpp"
    #include <pythonic/include/numpy/array.hpp>
    #include <pythonic/numpy/array.hpp>
    #include "pythonic/include/utils/array_helper.hpp"
    #include "pythonic/include/types/ndarray.hpp"

    using namespace pythonic;

    // Helper to create a float 1D array from a pointer
    template <typename T>
    types::ndarray<T, types::pshape<long>> arrayFromBuf1D(T* fPtr, long size) {
        auto shape = types::pshape<long>(size);
        return types::ndarray<T, types::pshape<long>>(fPtr,shape,types::ownership::external);
    }

    #define MAX_NUM_SAMPS 500*44100
    int main()
    {
        // Read audio
        char* fileName = "./police.raw";
        long L = MAX_NUM_SAMPS;
        std::unique_ptr<float[]> ptr(new float[L]);
        FILE* fd = fopen(fileName,"rb");
        L = fread(ptr.get(),sizeof(float),L,fd);
        printf("Read %d samples\n",L);
        fclose(fd);

        // Create array from our buffer
        auto inputArray = arrayFromBuf1D(ptr.get(),L);

        // Call process:
        auto t1 = std::chrono::system_clock::now();
        auto outputArray = __pythran_time_scaling::process()(inputArray,44100.,1.2f);
        auto t2 = std::chrono::system_clock::now();
        printf("Elapsed: %d ms\n", std::chrono::duration_cast<std::chrono::milliseconds>(t2 - t1).count());

        // Now save to a binary float file:
        FILE* fdout = fopen("out.raw","wb");
        long numSamps = outputArray.size();
    //    printf("NumSamps = %d\n",numSamps);
        fwrite(outputArray.buffer,sizeof(float),numSamps,fdout);

        fclose(fdout);
        return 0;
    }

In this code, I'm reading a raw file into a float array, and I create a Pythran 1D array from the float buffer.
Note the extra pair of parentheses in the call to process:

::

    auto outputArray = __pythran_time_scaling::process()(inputArray,44100.,1.2f);


Similary, the process function returns a Numpy array, and the output signal is in the array's buffer. It's pretty straightforward to get the size of the array, and a pointer to its data. The size is obtained with:

::

    long numSamps = outputArray.size();

and the pointer to the float data is simply:

::
    outputArray.buffer


I find it easier to create a Makefile to run Pythran and then the compiler. In installed pythran in a virtual env in $HOME/Dev/PythranTest/MAIN/venv so my makefile looks like this:

::

    VENV = $$HOME/Dev/PythranTest/MAIN/venv
    IDIR1 = $(VENV)/lib/python2.7/site-packages/pythran
    IDIR2 = $(VENV)/lib/python2.7/site-packages/numpy/core/include
    IDIR3 = $(VENV)/include/python2.7
    OFLAG = -O2
    PFLAG = -DUSE_XSIMD -fopenmp

    main: main.cpp time_scaling.cpp
            c++ -std=c++11 $(OFLAG) -w -I$(IDIR1) -I$(IDIR2) -I$(IDIR3) -undefined dynamic_lookup -march=native -F. main.cpp -o main

    time_scaling.cpp: time_scaling.py
            @echo "\033[0;36mRunning pythran\033[0m"
            pythran -e $(PFLAG) time_scaling.py

    clean:
            rm -f time_scaling.cpp main

Note that you can use pythran-config --cflags --libs to find out what include paths are needed in your case. Also note that since I'm not making any call to functions that need blas (linear algebra functions) I do not need to link with the blas libraries so I've omitted it from my makefile.
With this makefile, all you need to do is make main, and Pythran will first be run to create time_scaling.cpp then c++ will be called to compile main.cpp into main. I'm using the -march=native flag for maximum efficiency of the executable.

Now main is a completely free-standing executable that does not need any library, and is 100% independent from Python or Numpy. You can run it from the console.
It's even faster than the Python/Pythran version: the program reports:

::

    Read 12436200 samples
    Elapsed: 1565 ms

So that's 1.56s down from 1.87s for the Python/Pythran version, a further 15% speed improvement!

A final note on time-scaling
__________________________________

The algorithm I used in this blog post achieves good results in many cases, but not in all cases. For one, results are usually better when speeding up rather than slowing down audio. One of the biggest problems with this simple algorithm is that it does not do well when the audio includes sharp transients (for example, drums, percussions, etc). You'll notice that the transients become smeared in time, lose their sharpness. Many improvements have been suggested to alleviate this problem, see for example `this paper <http://www.ircam.fr/equipes/analyse-synthese/roebel/paper/dafx2003.pdf>`_.


Conclusion
===============

I hope this example will have convinced you. Python/Numpy is a great prototyping language: high-level, flexible, fast enough for rapid prototyping, it has all the features one might want for algorithm prototyping. Now with Pythran you can turn this high-level interpreted code into a blazingly fast C++ version that no longer depends on Python or Numpy, can be included into your C++ project, and compiled to any target you might like. In addition, if the code you're deploying contains some proprietary IP, the translation to C++ and compilation to machine code makes reverse-engineering it far harder than if it was deployed using python, even with obfuscation.

Pythran has some limitations: you cannot use classes, and polymorphism is limited to some degree. In practice, I find these limitations acceptable (the lack of class support is the one that I find the most cumbersome), given the efficiency of the C++ code that's generated.

.. _Paper: http://www.cs.bu.edu/fac/snyder/cs591/Literature%20and%20Resources/ImprovedPhaseVocoderTimeScaleMod.pdf

.. _entry: https://en.wikipedia.org/wiki/Audio_time_stretching_and_pitch_scaling

