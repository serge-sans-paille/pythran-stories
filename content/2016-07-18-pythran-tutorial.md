Title: Pythran Tutorial
Date: 2016-07-18
Category: examples
Lang: en
Authors: serge-sans-paille
Summary: Learn how to use Pythran, in a notebook or in a shell. Including some unusual Pythran tricks ;-)

Pythran presentation hold on Université Lyon1 on Monday 27th June together with a Julia presentation, and later at [Compas'2016](http://compas2016.sciencesconf.org/).

This blogpost originally was a Jupyter Notebook. You can [download it](notebooks/Pythran Tutorial.ipynb) if you want. The conversion was done using ``nbconvert`` and a [custom template](notebooks/nbmarkdown.tpl) to match the style of the other part of the blog.


## Prelude

Pythran is a compiler that turns numerical kernels into native modules.

You can download it on:

- PyPI: ``pip install pythran``
- Conda: ``conda install pythran``

Linux, OSX and Windows (through WinPython) are supported.

Partial Python3 support.

# Introduction with Pi computation

Computing $\pi$ is quite old fashined, but it's a good start to learn Pythran!

Here is a Fortran-like version:


```python
>>> def pi_approximate(n):
...     step = 1.0 / n
...     result = 0   
...     for i in range(n):
...         x = (i + 0.5) * step
...         result += 4.0 / (1.0 + x * x)
...     return step * result
... 
>>> pi_approximate(1000000)
```

We can get a first glimpse of its performance using the ``timeit`` module:


```python
>>> %timeit pi_approximate(1000000)
```

Turning this code into Pythran code is relatively easy. First we need to import Pythran:


```python
>>> import pythran
```

And load it's notebook integration mode:


```python
>>> %load_ext pythran.magic
```

Now we'll just reproduce the code above, with an additionnal line to tell pythran about the argument type. the return type is infered.


```python
>>> %%pythran
>>> #pythran export pi_approximate_pythran(int)
>>> import numpy as np
>>> def pi_approximate_pythran(n):
...     step = 1.0 / n
...     result = 0   
...     for i in range(n):
...         x = (i + 0.5) * step
...         result += 4.0 / (1.0 + x * x)
...     return step * result
```

Hopefully, the code behaves the same:


```python
>>> pi_approximate_pythran(1000000)
```

But it runs faster!


```python
>>> %timeit pi_approximate_pythran(1000000)
```

Can we go faster? The astute reader has already noticed that the loop can run in parallel, so let's use OpenMP integration:


```python
>>> %%pythran -fopenmp
>>> #pythran export pi_approximate_pythran_omp(int)
>>> import numpy as np
>>> def pi_approximate_pythran_omp(n):
...     step = 1.0 / n
...     result = 0
...     #omp parallel for reduction(+:result)
...     for i in range(n):
...         x = (i + 0.5) * step
...         result += 4.0 / (1.0 + x * x)
...     return step * result
```


```python
>>> %timeit pi_approximate_pythran_omp(1000000)
```

But everything looks very Fortran-ish in this example. Why not trying the following:


```python
>>> import numpy as np
>>> def pi_numpy_style(n):
...     step = 1.0 / n
...     x = (np.arange(0, n, dtype=np.float64) + 0.5) * step
...     return step * np.sum(4. / (1. + x ** 2))
```

It works the same, but it's already faster as most of the computations are done using native code:


```python
>>> pi_numpy_style(1000000)
```


```python
>>> %timeit pi_numpy_style(1000000)
```

Good new! Pythran can also handle this version, without much changes:


```python
>>> %%pythran
>>> #pythran export pi_numpy_style_pythran(int)
>>> import numpy as np
>>> def pi_numpy_style_pythran(n):
...     step = 1.0 / n
...     x = (np.arange(0, n, dtype=np.float64) + 0.5) * step
...     return step * np.sum(4. / (1. + x ** 2))
```

It still works, and runs almost as fast as the numpy-free version converted by Pythran:


```python
>>> pi_numpy_style_pythran(1000000)
```


```python
>>> %timeit pi_numpy_style_pythran(1000000)
```

Cherry on the cake: Pythran can take advantage of the vectorized code to generate SIMD code:


```python
>>> %%pythran -DUSE_BOOST_SIMD -march=native
>>> #pythran export pi_numpy_style_pythran_simd(int)
>>> import numpy as np
>>> def pi_numpy_style_pythran_simd(n):
...     step = 1.0 / n
...     x = (np.arange(0, n, dtype=np.float64) + 0.5) * step
...     return step * np.sum(4. / (1. + x ** 2))
```


```python
>>> %timeit pi_numpy_style_pythran_simd(1000000)
```

## Pythran in a nutshell

- DSL embeded into Python (no technological debt)
- Minimalists type annotations (only the exported functions)
- Parallelization and Vectorization are possible
- Supports (an already large part of) Numpy and Python builtins

# Type Annotations

Consider the following function:


```python
>>> def pairwise_distance(X):
...     return np.sqrt(((X[:, None, :] - X) ** 2).sum(-1))
```

It makes use of fancy indexing, broadcasting and Numpy. And it's polymorphic!


```python
>>> size = 100
>>> args32 = np.random.random((size, size)).astype(np.float32)
>>> args64 = np.random.random((size, size)).astype(np.float64)  #cast useless
>>> %timeit pairwise_distance(args32)
>>> %timeit pairwise_distance(args64)
```

Pythran can handle all of this! Note the double export to specify the overloads:


```python
>>> %%pythran
>>> import numpy as np
>>> #pythran export pairwise_distance_pythran(float32[][])
>>> #pythran export pairwise_distance_pythran(float64[:,:])
>>> def pairwise_distance_pythran(X):
...     print X.dtype
...     return np.sqrt(((X[:, None, :] - X) ** 2).sum(-1))
```


```python
>>> print pairwise_distance_pythran(args32).dtype
>>> %timeit pairwise_distance_pythran(args32)
>>> print pairwise_distance_pythran(args64).dtype
>>> %timeit pairwise_distance_pythran(args64)
```

Pythran also automatically handles transposed arguments, without making a copy:


```python
>>> pairwise_distance_pythran(args64.T)
```

There's more than arrays and scalars in Pythran types. What about... a tuple of tuple of complex numbers, lists and sets?


```python
>>> %%pythran
>>> #pythran export wtf((int, complex128, (int set, int list, int:str dict)))
>>> def wtf(x):
...     return x
```


```python
>>> wtf(1)
```


```python
>>> strange_arg = 42, 1 + 1j, ({1, 2, 3}, [1, 2,3], {1: 'unan', 2: 'daou', 3: 'tri'})
>>> wtf(strange_arg)
```

Beware that Pythran works on a copy when passing ``tuple``, ``list``, ``set`` or ``dict`` in the Pythran world (it's ok for ``ndarray`` as it does not copy the whole data):


```python
>>> wtf(strange_arg) is strange_arg
```

Sometimes, you feel like using very long function prototypes. In that case use multi-line exports:


```python
>>> %%pythran
... 
>>> #pythran export my(bool,
>>> #                  bool,
>>> #                  bool,
>>> #                  bool)
>>> def my(ga, bu, zo, meu):
...     pass
```


```python
>>> my
```




    <function pythranized_91f76c58891b91073f8e4e4dae8d0989.my>




```python
>>> type(my(True, True, True, True))
```




    NoneType



Default arguments are taken into account, but they must be exported explictely:


```python
>>> %%pythran
>>> #pythran export pi_numpy_style_pythran_default(int)
>>> #pythran export pi_numpy_style_pythran_default()
>>> import numpy as np
>>> def pi_numpy_style_pythran_default(n=1):
...     step = 1.0 / n
...     x = (np.arange(0, n, dtype=np.float64) + 0.5) * step
...     return step * np.sum(4. / (1. + x ** 2))
```


```python
>>> pi_numpy_style_pythran_default()
```




    3.2




```python
>>> pi_numpy_style_pythran_default(10)
```




    3.1424259850010987



# Compilation of Numpy Expressions

Pythran is well aware of high-level numpy expressions. Consider this function:


```python
>>> import numpy as np
>>> def vibr_energy(harmonic, anharmonic, i):
...     return np.exp(-harmonic * i - anharmonic * (i ** 2))
... 
>>> dat0, dat1 = np.random.random(1000000), np.random.random(1000000)
```


```python
>>> %timeit vibr_energy(dat0, dat1, 3.)
```

    10 loops, best of 3: 25.7 ms per loop


A typical way to optimize it would be to use the ``numexpr`` package:


```python
>>> import numexpr as ne
>>> def vibr_energy_numexpr(harmonic, anharmonic, i):
...     return ne.evaluate('exp(-harmonic * i - anharmonic * (i ** 2))')
```


```python
>>> vibr_energy_numexpr(dat0, dat1, 3.)  # maybe ne has a cache?
>>> %timeit vibr_energy_numexpr(dat0, dat1, 3.)
```

    100 loops, best of 3: 9.82 ms per loop


Pythran implements (roughly) the same optimizations as ``numexpr`` does:


```python
>>> %%pythran -DUSE_BOOST_SIMD -march=native -Ofast -fopenmp
... 
>>> import numpy as np
>>> #pythran export vibr_energy_pythran(float[], float[], float)
... 
>>> def vibr_energy_pythran(harmonic, anharmonic, i):
...     
...     return np.exp(-harmonic * i - anharmonic * (i ** 2))
```


```python
>>> %timeit vibr_energy_pythran(dat0, dat1, 3.)
```

    100 loops, best of 3: 4.87 ms per loop


Remember that Pythran can handle polymorphic code? Then let's try:


```python
>>> %%pythran
>>> import numpy as np
>>> #pythran export vibr_energy_pythran(float[], float[], float)
>>> #pythran export vibr_energy_pythran(float[], float[], float[])
>>> def vibr_energy_pythran(harmonic, anharmonic, i):
...     return np.exp(-harmonic * i - anharmonic * (i ** 2))
```


```python
>>> %timeit vibr_energy_pythran(dat0, dat1, dat0)
```

    100 loops, best of 3: 12.9 ms per loop


Broadcasting on the way!

# Using Pythran from the Command Line

Pythran can be used without a Jupyter notebook! It requires you to

1. Write your code to Pythranize into a seperate file;
2. Call the Pythran compiler.


```python
>>> %%file scrabble.py
>>> #pythran export scrabble_score(str, str:int dict)
>>> def scrabble_score(word, scoretable):
...     score = 0
...     for letter in word:
...         if letter in scoretable:
...             score += scoretable[letter]
...     return score
... 
```

    Writing scrabble.py


Using the package API, or simply ``pythran scrabble.py``


```python
>>> !python -m pythran.run -v scrabble.py
```

    [39mrunning build_ext[0m
    [39mrunning build_src[0m
    [39mbuild_src[0m
    [39mbuilding extension "scrabble" sources[0m
    [39mbuild_src: building npy-pkg config files[0m
    [36mnew_compiler returns distutils.unixccompiler.UnixCCompiler[0m
    [32mINFO    [0m [34mcustomize UnixCCompiler[0m
    [39mcustomize UnixCCompiler using build_ext[0m
    ********************************************************************************
    distutils.unixccompiler.UnixCCompiler
    linker_exe    = ['x86_64-linux-gnu-gcc', '-pthread']
    compiler_so   = ['x86_64-linux-gnu-gcc', '-pthread', '-DNDEBUG', '-g', '-fwrapv', '-O2', '-Wall', '-Wstrict-prototypes', '-fno-strict-aliasing', '-g', '-O2', '-fPIC']
    archiver      = ['x86_64-linux-gnu-gcc-ar', 'rc']
    preprocessor  = ['x86_64-linux-gnu-gcc', '-pthread', '-E']
    linker_so     = ['x86_64-linux-gnu-gcc', '-pthread', '-shared', '-Wl,-O1', '-Wl,-Bsymbolic-functions', '-Wl,-z,relro', '-fno-strict-aliasing', '-DNDEBUG', '-g', '-fwrapv', '-O2', '-Wall', '-Wstrict-prototypes', '-Wdate-time', '-D_FORTIFY_SOURCE=2', '-g', '-fstack-protector-strong', '-Wformat', '-Werror=format-security', '-Wl,-z,relro', '-g', '-O2']
    compiler_cxx  = ['c++', '-pthread']
    ranlib        = None
    compiler      = ['x86_64-linux-gnu-gcc', '-pthread', '-DNDEBUG', '-g', '-fwrapv', '-O2', '-Wall', '-Wstrict-prototypes', '-fno-strict-aliasing', '-g', '-O2']
    libraries     = []
    library_dirs  = []
    include_dirs  = ['/usr/include/python2.7']
    ********************************************************************************
    [36mnew_compiler returns distutils.unixccompiler.UnixCCompiler[0m
    [32mINFO    [0m [34mcustomize UnixCCompiler[0m
    [39mcustomize UnixCCompiler using build_ext[0m
    ********************************************************************************
    distutils.unixccompiler.UnixCCompiler
    linker_exe    = ['x86_64-linux-gnu-gcc', '-pthread']
    compiler_so   = ['x86_64-linux-gnu-gcc', '-pthread', '-DNDEBUG', '-g', '-fwrapv', '-O2', '-Wall', '-fno-strict-aliasing', '-g', '-O2', '-fPIC']
    archiver      = ['x86_64-linux-gnu-gcc-ar', 'rc']
    preprocessor  = ['x86_64-linux-gnu-gcc', '-pthread', '-E']
    linker_so     = ['x86_64-linux-gnu-gcc', '-pthread', '-shared', '-Wl,-O1', '-Wl,-Bsymbolic-functions', '-Wl,-z,relro', '-fno-strict-aliasing', '-DNDEBUG', '-g', '-fwrapv', '-O2', '-Wall', '-Wstrict-prototypes', '-Wdate-time', '-D_FORTIFY_SOURCE=2', '-g', '-fstack-protector-strong', '-Wformat', '-Werror=format-security', '-Wl,-z,relro', '-g', '-O2']
    compiler_cxx  = ['c++', '-pthread']
    ranlib        = None
    compiler      = ['x86_64-linux-gnu-gcc', '-pthread', '-DNDEBUG', '-g', '-fwrapv', '-O2', '-Wall', '-Wstrict-prototypes', '-fno-strict-aliasing', '-g', '-O2']
    libraries     = []
    library_dirs  = []
    include_dirs  = ['/usr/include/python2.7']
    ********************************************************************************
    [39mbuilding 'scrabble' extension[0m
    [39mcompiling C++ sources[0m
    [39mC compiler: c++ -pthread -DNDEBUG -g -fwrapv -O2 -Wall -fno-strict-aliasing -g -O2 -fPIC
    [0m
    [39mcreating /tmp/tmpiXxCc3/tmp[0m
    [39mcompile options: '-DUSE_GMP -DENABLE_PYTHON_MODULE -I/home/sguelton/sources/pythran/pythran -I/home/sguelton/sources/pythran/pythran/pythonic/patch -I/home/sguelton/.venvs/pythran-demo/local/lib/python2.7/site-packages/numpy/core/include -I/usr/include/python2.7 -c'
    extra options: '-std=c++11 -fno-math-errno -w -fwhole-program -fvisibility=hidden'[0m
    [39mc++: /tmp/tmpRIF8Kz.cpp[0m
    [36mexec_command(['c++', '-pthread', '-DNDEBUG', '-g', '-fwrapv', '-O2', '-Wall', '-fno-strict-aliasing', '-g', '-O2', '-fPIC', '-DUSE_GMP', '-DENABLE_PYTHON_MODULE', '-I/home/sguelton/sources/pythran/pythran', '-I/home/sguelton/sources/pythran/pythran/pythonic/patch', '-I/home/sguelton/.venvs/pythran-demo/local/lib/python2.7/site-packages/numpy/core/include', '-I/usr/include/python2.7', '-c', '/tmp/tmpRIF8Kz.cpp', '-o', '/tmp/tmpiXxCc3/tmp/tmpRIF8Kz.o', '-std=c++11', '-fno-math-errno', '-w', '-fwhole-program', '-fvisibility=hidden'],)[0m
    [36mRetaining cwd: /home/sguelton/sources/pythran/notebooks[0m
    [36m_preserve_environment([])[0m
    [36m_update_environment(...)[0m
    [36m_exec_command_posix(...)[0m
    [36mRunning os.system('( c++ -pthread -DNDEBUG -g -fwrapv -O2 -Wall -fno-strict-aliasing -g -O2 -fPIC -DUSE_GMP -DENABLE_PYTHON_MODULE -I/home/sguelton/sources/pythran/pythran -I/home/sguelton/sources/pythran/pythran/pythonic/patch -I/home/sguelton/.venvs/pythran-demo/local/lib/python2.7/site-packages/numpy/core/include -I/usr/include/python2.7 -c /tmp/tmpRIF8Kz.cpp -o /tmp/tmpiXxCc3/tmp/tmpRIF8Kz.o -std=c++11 -fno-math-errno -w -fwhole-program -fvisibility=hidden ; echo $? > /tmp/tmpkJNNfR/XwPT61 ) 2>&1 | tee /tmp/tmpkJNNfR/xJbGUl ')[0m
    [36m_update_environment(...)[0m
    [39mc++ -pthread -shared -Wl,-O1 -Wl,-Bsymbolic-functions -Wl,-z,relro -fno-strict-aliasing -DNDEBUG -g -fwrapv -O2 -Wall -Wstrict-prototypes -Wdate-time -D_FORTIFY_SOURCE=2 -g -fstack-protector-strong -Wformat -Werror=format-security -Wl,-z,relro -g -O2 /tmp/tmpiXxCc3/tmp/tmpRIF8Kz.o -lgmp -lgmpxx -lcblas -lblas -o /tmp/tmpsa8TH1/scrabble.so -fvisibility=hidden -Wl,-strip-all[0m
    [36mexec_command(['c++', '-pthread', '-shared', '-Wl,-O1', '-Wl,-Bsymbolic-functions', '-Wl,-z,relro', '-fno-strict-aliasing', '-DNDEBUG', '-g', '-fwrapv', '-O2', '-Wall', '-Wstrict-prototypes', '-Wdate-time', '-D_FORTIFY_SOURCE=2', '-g', '-fstack-protector-strong', '-Wformat', '-Werror=format-security', '-Wl,-z,relro', '-g', '-O2', '/tmp/tmpiXxCc3/tmp/tmpRIF8Kz.o', '-lgmp', '-lgmpxx', '-lcblas', '-lblas', '-o', '/tmp/tmpsa8TH1/scrabble.so', '-fvisibility=hidden', '-Wl,-strip-all'],)[0m
    [36mRetaining cwd: /home/sguelton/sources/pythran/notebooks[0m
    [36m_preserve_environment([])[0m
    [36m_update_environment(...)[0m
    [36m_exec_command_posix(...)[0m
    [36mRunning os.system('( c++ -pthread -shared -Wl,-O1 -Wl,-Bsymbolic-functions -Wl,-z,relro -fno-strict-aliasing -DNDEBUG -g -fwrapv -O2 -Wall -Wstrict-prototypes -Wdate-time -D_FORTIFY_SOURCE=2 -g -fstack-protector-strong -Wformat -Werror=format-security -Wl,-z,relro -g -O2 /tmp/tmpiXxCc3/tmp/tmpRIF8Kz.o -lgmp -lgmpxx -lcblas -lblas -o /tmp/tmpsa8TH1/scrabble.so -fvisibility=hidden -Wl,-strip-all ; echo $? > /tmp/tmpkJNNfR/KjbDFo ) 2>&1 | tee /tmp/tmpkJNNfR/LHI7ms ')[0m
    [36m_update_environment(...)[0m
    [32mINFO    [0m [34mGenerated module: scrabble[0m
    [32mINFO    [0m [34mOutput: /home/sguelton/sources/pythran/notebooks/scrabble.so[0m



```python
>>> import scrabble
```


```python
>>> scrabble.__file__
```




    'scrabble.so'




```python
>>> scrabble.scrabble_score("hello", {"h": 4, "e": 1, "l": 1, "o": 1})
```




    8



# Using Pythran with distutils

Pythran provides some facilities for distutils integration, in the form of a ``PythranExtension``:


```python
>>> %%file setup.py
>>> from distutils.core import Extension
>>> from setuptools import setup, dist
... 
>>> dist.Distribution(dict(setup_requires='pythran'))
... 
>>> from pythran import PythranExtension
>>> module1 = PythranExtension('demo', sources = ['scrabble.py'])
... 
>>> setup(name = 'demo',
...       version = '1.0',
...       description = 'This is a demo package',
...       ext_modules = [module1])
... 
```

    Writing setup.py



```python
>>> !python setup.py build -v
```

    [39mrunning build[0m
    [39mrunning build_ext[0m
    [39mbuilding 'demo' extension[0m
    [39mC compiler: x86_64-linux-gnu-gcc -pthread -DNDEBUG -g -fwrapv -O2 -Wall -Wstrict-prototypes -fno-strict-aliasing -g -O2 -fPIC
    [0m
    [39mcreating build[0m
    [39mcreating build/temp.linux-x86_64-2.7[0m
    [39mcompile options: '-DUSE_GMP -DENABLE_PYTHON_MODULE -I/home/sguelton/sources/pythran/pythran -I/home/sguelton/sources/pythran/pythran/pythonic/patch -I/usr/include/python2.7 -c'
    extra options: '-std=c++11 -fno-math-errno -w -fwhole-program -fvisibility=hidden'[0m
    [39mx86_64-linux-gnu-gcc: scrabble.cpp[0m
    cc1plus: warning: command line option ‘-Wstrict-prototypes’ is valid for C/ObjC but not for C++
    [39mcreating build/lib.linux-x86_64-2.7[0m
    [39mc++ -pthread -shared -Wl,-O1 -Wl,-Bsymbolic-functions -Wl,-z,relro -fno-strict-aliasing -DNDEBUG -g -fwrapv -O2 -Wall -Wstrict-prototypes -Wdate-time -D_FORTIFY_SOURCE=2 -g -fstack-protector-strong -Wformat -Werror=format-security -Wl,-z,relro -g -O2 build/temp.linux-x86_64-2.7/scrabble.o -lgmp -lgmpxx -lcblas -lblas -o build/lib.linux-x86_64-2.7/demo.so -fvisibility=hidden -Wl,-strip-all[0m



```python
>>> !python setup.py sdist
```

    [39mrunning sdist[0m
    [39mrunning egg_info[0m
    [39mwriting demo.egg-info/PKG-INFO[0m
    [39mwriting top-level names to demo.egg-info/top_level.txt[0m
    [39mwriting dependency_links to demo.egg-info/dependency_links.txt[0m
    [39mreading manifest file 'demo.egg-info/SOURCES.txt'[0m
    [39mwriting manifest file 'demo.egg-info/SOURCES.txt'[0m
    [31mwarning: sdist: standard file not found: should have one of README, README.rst, README.txt
    [0m
    [39mrunning check[0m
    [31mwarning: check: missing required meta-data: url
    [0m
    [31mwarning: check: missing meta-data: either (author and author_email) or (maintainer and maintainer_email) must be supplied
    [0m
    [39mcreating demo-1.0[0m
    [39mcreating demo-1.0/demo.egg-info[0m
    [39mmaking hard links in demo-1.0...[0m
    [39mhard linking scrabble.cpp -> demo-1.0[0m
    [39mhard linking setup.py -> demo-1.0[0m
    [39mhard linking demo.egg-info/PKG-INFO -> demo-1.0/demo.egg-info[0m
    [39mhard linking demo.egg-info/SOURCES.txt -> demo-1.0/demo.egg-info[0m
    [39mhard linking demo.egg-info/dependency_links.txt -> demo-1.0/demo.egg-info[0m
    [39mhard linking demo.egg-info/top_level.txt -> demo-1.0/demo.egg-info[0m
    [39mWriting demo-1.0/setup.cfg[0m
    [39mcreating dist[0m
    [39mCreating tar archive[0m
    [39mremoving 'demo-1.0' (and everything under it)[0m



```python
>>> !tar tzf dist/demo-1.0.tar.gz
```

    demo-1.0/
    demo-1.0/PKG-INFO
    demo-1.0/scrabble.cpp
    demo-1.0/demo.egg-info/
    demo-1.0/demo.egg-info/PKG-INFO
    demo-1.0/demo.egg-info/SOURCES.txt
    demo-1.0/demo.egg-info/dependency_links.txt
    demo-1.0/demo.egg-info/top_level.txt
    demo-1.0/setup.py
    demo-1.0/setup.cfg


# Getting Help

- GitHub: https://github.com/serge-sans-paille/pythran
- Mailing list: http://www.freelists.org/list/pythran
- IRC: #pythran on FreeNode
- StackOverflow: http://stackoverflow.com/questions/tagged/pythran

# Misc

Things you probably don't want to know, but they were fun to implement, so let's talk about them anyway :-)

## Functions as regular values


```python
>>> %%pythran
>>> #pythran export modify(int, str)
>>> actions = {"increase": lambda x: x + 1,
...            "decrease": lambda x: x - 1}
... 
>>> def modify(value, action):
...     what = actions[action]
...     return what(value)
```


```python
>>> modify(1, "increase")
```




    2



Passing functions in and out is not supported though.

## Big Numbers

Not widely supported, but it works for simple examples.


```python
>>> %%pythran
>>> #pythran export factorize_naive(long)
>>> def factorize_naive(n):
...     if n < 2:
...         return []
...     
...     factors = []
...     
...     p = 2L
... 
...     while True:
...         if n == 1:
...             return factors
... 
...         r = n % p
...         if r == 0:
...             factors.append(p)
...             n = n / p
...         elif p * p >= n:
...             factors.append(n)
...             return factors
...         elif p > 2:
...             # Advance in steps of 2 over odd numbers
...             p += 2
...         else:
...             # If p == 2, get to 3
...             p += 1
...     assert False, "unreachable"
```


```python
>>> %timeit factorize_naive(3241618756762348687L)
```

    1 loop, best of 3: 2 s per loop


### Cleanup before you leave the room ;-)


```python
>>> !rm -rf build dist scrabble.py setup.py scrabble.so # cleanup
```
