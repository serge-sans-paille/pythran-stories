Title: Costless Abstraction with Pythran: Broadcasting
Date: 2016-05-25
Category: optimisation
Lang: en
Authors: serge-sans-paille
Summary: Broadcasting is a neat feature of Numpy array, but it was not trivial
         to implement at the C++ level, while keeping a high-level interface. after
         weeks of effort, here is a showcase of how good it runs, compared to the Numpy
         version and lower-level Cython and Numba version!

This blogpost originally was a Jupyter Notebook. You can [download it](notebooks/broadcasting.ipynb) if you want. The conversion was done using ``nbconvert`` and a [custom template](notebooks/nbmarkdown.tpl) to match the style of the other part of the blog.


# Numpy's Broadcasting

Broadcasting is a neat feature of Numpy (and other similar array-oriented languages like Matlab). It makes it possible to avoid explicit loops on arrays (they are particularly inefficient in Numpy), and improves the abstraction level of your code, which is a good thing if you share the same abstraction.

For instance, the addition between two 1D array when one of them only holds a single element is well defined: the single element is repeated along the axis:


```python
>>> import numpy as np
```


```python
>>> a, b = np.arange(10), np.array([10])
>>> a + b
```




    array([10, 11, 12, 13, 14, 15, 16, 17, 18, 19])



Which is very similar to the addition between an array and a scalar, *btw*.

So to store all the possible multiplication between two 1D arrays, one can create a new axis and turn them into 2D arrays, then use this broadcasting facility:


```python
>>> a, b = np.array([1,2,4,8]), np.array([1, 3, 7, 9])
>>> a[np.newaxis, :] * b[:, np.newaxis]
```




    array([[ 1,  2,  4,  8],
           [ 3,  6, 12, 24],
           [ 7, 14, 28, 56],
           [ 9, 18, 36, 72]])



# Broadcasting and Pythran

Pythran uses [expression templates](https://en.wikipedia.org/wiki/Expression_templates) to optimize array expression, and end up with something that is similar to [numexpr](https://github.com/pydata/numexpr) performance wise.

It's relatively easy for Pythran's expression template to broadcast between array and scalars, or between two arrays that don't have the same dimension, as the information required to perform the broadcasting is part of the type, thus it's known at compile time.

But the broadcasting described above only depends on the size, and Pythran generally does not have access to it at compile time. So a dynamic behavior is needed. Roughly speaking, instead of explicitly iterating over the expression template, iterators parametrized by a step are used. This step is equal to one for regular operands, and to zero for broadcast operands, which results in part of the operator always repeating itself.

What's its cost? Let's benchmark :-)

## Numpy implementation

The original code performs a reduction over a broadcast multiplication. When doing so Numpy creates a temporary 2D array, then computes the sum. Using ``None`` for indexing is similar to ``np.newaxis``.


```python
>>> def broadcast_numpy(x, y):
...     return (x[:, None] * y[None, :]).sum()
```

## Pythran Implementation

The Pythran implementation is straight-forward: just add the right annotation.

*Note: The pythran magic is not available as is in pythran 0.7.4 or lower*


```python
>>> %load_ext pythran.magic
```


```python
>>> %%pythran -O3
>>> #pythran export broadcast_pythran(float64[], float64[])
>>> def broadcast_pythran(x, y):
...     return (x[:, None] * y[None, :]).sum()
```

## Cython Implementation

The Cython implementation makes the looping explicit. We use all the tricks we know to get a fast version: ``@cython.boundscheck(False)``, ``@cython.wraparound(False)`` and a manual look at the output of ``cython -a``.


```python
>>> %load_ext Cython
```


```python
>>> %%cython --compile-args=-O3
>>> 
>>> import cython
>>> import numpy as np
>>> cimport numpy as np
>>> 
>>> @cython.boundscheck(False)
>>> @cython.wraparound(False)
>>> def broadcast_cython(double[::1] x, double[::1] y):
...     cdef int n = len(x)
...     cdef int i, j
...     cdef double res = 0
...     for i in xrange(n):
...         for j in xrange(n):
...             res += x[i] * y[j]
...     return res
```

## Numba Implementation

The Numba version is very similar to the Cython one, without the need of declaring the actual types.


```python
>>> import numba
>>> @numba.jit
>>> def broadcast_numba(x, y):
...     n = len(x)
...     res = 0
...     for i in xrange(n):
...         for j in xrange(n):
...             res += x[i] * y[j]
...     return res
```

## Sanity Check

Just to be sure all versions yield the same value :-)


```python
>>> from collections import OrderedDict
>>> functions = OrderedDict()
>>> functions['numpy'] = broadcast_numpy
>>> functions['cython'] = broadcast_cython
>>> functions['pythran'] = broadcast_pythran
>>> functions['numba'] = broadcast_numba
```


```python
>>> x = np.random.random(10).astype('float64')
>>> y = np.random.random(10).astype('float64')
>>> for name, function in functions.items():
...     print name, function(x, y)
```

    numpy 21.4640902072
    cython 21.4640902072
    pythran 21.4640902072
    numba 21.4640902072


# Benchmark

The actual benchmark just runs each function through ``timeit`` for various array sizes.


```python
>>> import timeit
>>> sizes = [1e3, 5e3, 1e4]
>>> import pandas
>>> scores = pandas.DataFrame(data=0, columns=functions.keys(), index=sizes)
>>> for size in sizes:
...     size = int(size)
...     for name, function in functions.items():
...         print name, " ",
...         x = np.random.random(size).astype('float64')
...         y = np.random.random(size).astype('float64')
...         result = %timeit -o function(x, y)
...         scores.loc[size, name] = result.best
```

    numpy  1000 loops, best of 3: 1.81 ms per loop
     cython  1000 loops, best of 3: 847 µs per loop
     pythran  1000 loops, best of 3: 846 µs per loop
     numba  1000 loops, best of 3: 847 µs per loop
     numpy  10 loops, best of 3: 80.8 ms per loop
     cython  10 loops, best of 3: 21.1 ms per loop
     pythran  10 loops, best of 3: 21.2 ms per loop
     numba  10 loops, best of 3: 21.2 ms per loop
     numpy  1 loop, best of 3: 248 ms per loop
     cython  10 loops, best of 3: 84.9 ms per loop
     pythran  10 loops, best of 3: 84.8 ms per loop
     numba  10 loops, best of 3: 84.8 ms per loop
    


## Results (time in seconds, lower is better) 


```python
>>> scores
```




<div>
<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th></th>
      <th>numpy</th>
      <th>cython</th>
      <th>pythran</th>
      <th>numba</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>1000.0</th>
      <td>0.001809</td>
      <td>0.000847</td>
      <td>0.000846</td>
      <td>0.000847</td>
    </tr>
    <tr>
      <th>5000.0</th>
      <td>0.080827</td>
      <td>0.021096</td>
      <td>0.021222</td>
      <td>0.021157</td>
    </tr>
    <tr>
      <th>10000.0</th>
      <td>0.248488</td>
      <td>0.084851</td>
      <td>0.084849</td>
      <td>0.084834</td>
    </tr>
  </tbody>
</table>
</div>



## Comparison to Numpy time (lower is better)


```python
>>> normalized_scores = scores.copy()
>>> for column in normalized_scores.columns:
...     normalized_scores[column] /= scores['numpy']    
```


```python
>>> normalized_scores
```




<div>
<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th></th>
      <th>numpy</th>
      <th>cython</th>
      <th>pythran</th>
      <th>numba</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>1000.0</th>
      <td>1.0</td>
      <td>0.468133</td>
      <td>0.467495</td>
      <td>0.468023</td>
    </tr>
    <tr>
      <th>5000.0</th>
      <td>1.0</td>
      <td>0.260999</td>
      <td>0.262561</td>
      <td>0.261762</td>
    </tr>
    <tr>
      <th>10000.0</th>
      <td>1.0</td>
      <td>0.341468</td>
      <td>0.341463</td>
      <td>0.341400</td>
    </tr>
  </tbody>
</table>
</div>



## Partial Conclusion

At first glance, Cython, Pythran and Numba all manage to get a decent speedup over the Numpy version. So what's the point?

1. Cython requires extra annotations, and explicit loops;
2. Numba only requires a decorator, but still explicit loops;
3. Pythran still requires a type annotation, but it keeps the Numpy abstraction.

That's Pythran Leitmotiv: keep the Numpy abstraction, but try hard to make it run faster!

# Round Two: Using the compiler

Gcc (and Clang, and…) provide two flags that can be useful in this situation: ``-Ofast`` and ``-march=native``. The former is generally equivalent to ``-O3`` with a few extra flags, most notably ``-ffast-math`` that disregards standard compliance with respect to floating point operation; In our case it makes it possible to reorder the operations to perform the final reduction using SIMD instructions. And with ``-march=native``, the code gets specialized for the host architecture. In the case of this post, It means it can use [AVX](https://en.wikipedia.org/wiki/Advanced_Vector_Extensions) and its 256bits vector register than can store four double precision floating!

In the Pythran case, vectorization is currently activated through the (somehow experimental) ``-DUSE_BOOST_SIMD`` flag.


```python
>>> %%pythran -O3 -march=native -DUSE_BOOST_SIMD
>>> #pythran export broadcast_pythran_simd(float64[], float64[])
>>> def broadcast_pythran_simd(x, y):
...     return (x[:, None] * y[None, :]).sum()
>>> 
```


```python
>>> %%cython -c=-Ofast -c=-march=native
>>> 
>>> import cython
>>> import numpy as np
>>> cimport numpy as np
>>> 
>>> @cython.boundscheck(False)
>>> @cython.wraparound(False)
>>> def broadcast_cython_simd(double[::1] x, double[::1] y):
...     cdef int n = len(x)
...     cdef int i, j
...     cdef double res = 0
...     for i in xrange(n):
...         for j in xrange(n):
...             res += x[i] * y[j]
...     return res
```

We can then rerun the previous benchmark, with these two functions


```python
>>> simd_functions = OrderedDict()
>>> simd_functions['numpy'] = broadcast_numpy
>>> simd_functions['cython+simd'] = broadcast_cython_simd
>>> simd_functions['pythran+simd'] = broadcast_pythran_simd
>>> simd_scores = pandas.DataFrame(data=0, columns=simd_functions.keys(), index=sizes)
>>> for size in sizes:
...     size = int(size)
...     for name, function in simd_functions.items():
...         print name, " ",
...         x = np.random.random(size).astype('float64')
...         y = np.random.random(size).astype('float64')
...         result = %timeit -o function(x, y)
...         simd_scores.loc[size, name] = result.best
```

    numpy  100 loops, best of 3: 1.8 ms per loop
     cython+simd  1000 loops, best of 3: 203 µs per loop
     pythran+simd  1000 loops, best of 3: 232 µs per loop
     numpy  10 loops, best of 3: 81.4 ms per loop
     cython+simd  100 loops, best of 3: 5.42 ms per loop
     pythran+simd  100 loops, best of 3: 5.98 ms per loop
     numpy  1 loop, best of 3: 249 ms per loop
     cython+simd  10 loops, best of 3: 21.5 ms per loop
     pythran+simd  10 loops, best of 3: 23.6 ms per loop
    



```python
>>> simd_scores
```




<div>
<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th></th>
      <th>numpy</th>
      <th>cython+simd</th>
      <th>pythran+simd</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>1000.0</th>
      <td>0.001797</td>
      <td>0.000203</td>
      <td>0.000232</td>
    </tr>
    <tr>
      <th>5000.0</th>
      <td>0.081422</td>
      <td>0.005419</td>
      <td>0.005984</td>
    </tr>
    <tr>
      <th>10000.0</th>
      <td>0.249028</td>
      <td>0.021458</td>
      <td>0.023631</td>
    </tr>
  </tbody>
</table>
</div>



## Conclusion

What happens there is that the underlying compiler is capable, on our simple case, to vectorize the loops and takes advantage of the vector register to speedup the computation. Although there's still a small overhead, Pythran is almost on par with Cython, even when vectorization is enabled, which means that the abstraction is still valid, even for complex feature like Numpy's broadcasting.

Under the hood though, the approach is totally different: Pythran vectorizes the expression template and generates calls to [boost.simd](https://github.com/NumScale/boost.simd), while Cython fully relies on gcc auto-vectorizer, which proves to be a good approach until one meets a code gcc cannot vectorize!

### Technical info


```python
>>> np.__version__
```




    '1.11.0'




```python
>>> import cython ; cython.__version__
```




    '0.24'




```python
>>> import pythran; pythran.__version__
```




    '0.7.4.post1'




```python
>>> numba.__version__
```




    '0.25.0'




```python
>>> !g++ --version
```

    g++-5.real (Debian 5.3.1-19) 5.3.1 20160509
    Copyright (C) 2015 Free Software Foundation, Inc.
    This is free software; see the source for copying conditions.  There is NO
    warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    

