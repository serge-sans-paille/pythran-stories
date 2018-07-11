Title: Testing Pythran on random kernels
Date: 2018-07-11
Category: examples
Lang: en
Authors: serge-sans-paille
Summary: Stack Overflow is a great place to find new challenging test case for Pythran :-)

This blogpost originally was a Jupyter Notebook. You can [download it](notebooks/Testing Pythran on random kernels.ipynb) if you want. The conversion was done using ``nbconvert`` and a [custom template](notebooks/nbmarkdown.tpl) to match the style of the other part of the blog.

Every now and then, I hang around on stackoverflow, longing for numerical kernels to pass through [pythran](https://pythran.readthedocs.io). Here is the result of my recent wanderings :-)


```python
>>> # It's import(ant)
>>> import pythran, numpy as np
>>> %load_ext pythran.magic
```

# From stackoverflow

## euclidian distance

from <https://stackoverflow.com/questions/50658884/why-this-numba-code-is-6x-slower-than-numpy-code> . This kernel is interesting because it uses ``np.newaxis``, ``np.sum``) along an axis, and a matrix against transposed matrix dot product.


```python
>>> import numpy as np
>>> def euclidean_distance_square(x1, x2):
...     return -2*np.dot(x1, x2.T) + np.expand_dims(np.sum(np.square(x1), axis=1), axis=1) + np.sum(np.square(x2), axis=1)
```


```python
>>> %%pythran
>>> #pythran export pythran_euclidean_distance_square(float64[1,:], float64[:,:])
>>> import numpy as np
>>> def pythran_euclidean_distance_square(x1, x2):
...     return -2*np.dot(x1, x2.T) + np.sum(np.square(x1), axis=1)[:, np.newaxis] + np.sum(np.square(x2), axis=1)
```


```python
>>> import numpy as np
>>> x1 = np.random.random((1, 512))
>>> x2 = np.random.random((10000, 512))
```


```python
>>> %timeit euclidean_distance_square(x1, x2)
>>> %timeit pythran_euclidean_distance_square(x1, x2)
```

    16.1 ms ± 905 µs per loop (mean ± std. dev. of 7 runs, 100 loops each)
    11.1 ms ± 76.5 µs per loop (mean ± std. dev. of 7 runs, 100 loops each)


As a side note, at some point in history, pythran failed to match the ``np.dot(x1, x2.T)`` pattern, but it now calls the appropriate blas API (``cblas_zgemm``) with the correct arguments, without copy.

## Updated centers

from <https://stackoverflow.com/questions/50931002/cython-numpy-array-manipulation-slower-than-python/50964759>. This is a funny kernel because of its use of list comprehension.


```python
>>> import numpy as np
>>> def updated_centers(point, start, center):
...     return np.array([__cluster_mean(point[start[c]:start[c + 1]], center[c]) for c in range(center.shape[0])])
... 
>>> def __cluster_mean(point, center):
...     return (np.sum(point, axis=0) + center) / (point.shape[0] + 1)
```


```python
>>> %%pythran
>>> #pythran export pythran_updated_centers(float64 [:, :], intc[:] , float64 [:, :] )
>>> import numpy as np
>>> def pythran_updated_centers(point, start, center):
...     return np.array([__cluster_mean(point[start[c]:start[c + 1]], center[c]) for c in range(center.shape[0])])
... 
>>> def __cluster_mean(point, center):
...     return (np.sum(point, axis=0) + center) / (point.shape[0] + 1)
```


```python
>>> import numpy as np
>>> n, m = 100000, 5
>>> k = n//2
>>> point = np.random.rand(n, m)
>>> start = 2*np.arange(k+1, dtype=np.int32)
>>> center=np.random.rand(k, m)
```


```python
>>> %timeit updated_centers(point, start, center)
>>> %timeit pythran_updated_centers(point, start, center)
```

    295 ms ± 18.9 ms per loop (mean ± std. dev. of 7 runs, 1 loop each)
    11.9 ms ± 71.7 µs per loop (mean ± std. dev. of 7 runs, 100 loops each)


That's a cool speedup, but that's normal: there is an explicit loop + array indexing pattern, and that's not where numpy shines.

## Gaussian Process

from <https://stackoverflow.com/questions/46334298/kernel-function-in-gaussian-processes>, a very high level kernel. The pythran version uses indexing through ``np.newaxis`` instead of the reshaping, and generates a specialized version for arguments where the last dimension is known to be one. There's two version of the pythran kernel, compiled with different flags to showcase the effect of vectorization.


```python
>>> import numpy as np
>>> def gp(a, b, gamma=0.1):
...     """ GP squared exponential kernel """
...     sq_dist = np.sum(a**2, 1).reshape(-1, 1) + np.sum(b**2, 1) - 2*np.dot(a, b.T)
...     return np.exp(-0.5 * (1 / gamma) * sq_dist)
```


```python
>>> %%pythran
>>> #pythran export pythran_gp_novect(float64[:,1], float64[:,1])
>>> import numpy as np
>>> def pythran_gp_novect(a, b, gamma=0.1):
...     """ GP squared exponential kernel """
...     sq_dist = np.sum(a**2, 1)[np.newaxis] + np.sum(b**2, 1) - 2*np.dot(a, b.T)
...     return np.exp(-0.5 * (1 / gamma) * sq_dist)
```


```python
>>> %%pythran -DUSE_BOOST_SIMD -march=native
>>> #pythran export pythran_gp_vect(float64[:,1], float64[:,1])
>>> import numpy as np
>>> def pythran_gp_vect(a, b, gamma=0.1):
...     """ GP squared exponential kernel """
...     sq_dist = np.sum(a**2, 1)[np.newaxis] + np.sum(b**2, 1) - 2*np.dot(a, b.T)
...     return np.exp(-0.5 * (1 / gamma) * sq_dist)
```


```python
>>> import numpy as np
>>> n = 300
>>> X = np.linspace(-5, 5, n).reshape(-1, 1)
```


```python
>>> %timeit gp(X, X)
>>> %timeit pythran_gp_novect(X, X)
>>> %timeit pythran_gp_vect(X, X)
```

    1.51 ms ± 6.73 µs per loop (mean ± std. dev. of 7 runs, 1000 loops each)
    1.21 ms ± 6.5 µs per loop (mean ± std. dev. of 7 runs, 1000 loops each)
    348 µs ± 20.1 µs per loop (mean ± std. dev. of 7 runs, 1000 loops each)


Not that much of a gain without vectorization enable, but still Pythran can rip a few extra performance out of a very high level kernel. Unleashing vectorization is plain awesome here :-)

## Image processing

from <https://stackoverflow.com/questions/45714178/python-improving-image-processing-with-numpy>, that's the kind of kernel where an explicit seems a natural fit, and where pythran shines.


```python
>>> def image_processing(A, B, sum_arr): # Proposed approach
...     B_ext = np.concatenate((B[1:], B))
...     n = len(A)
...     for i in range(n-1,-1,-1):
...         A *= B_ext[i:i+n] #roll B with i-increment and multiply
...         A[n-1-i] += sum_arr #add sum to A at index
...     return A
```


```python
>>> %%pythran
>>> import numpy as np
>>> #pythran export pythran_image_processing(int64[], int64[], int64)
>>> def pythran_image_processing(A, B, sum_arr): # Proposed approach
...     B_ext = np.concatenate((B[1:], B))
...     n = len(A)
...     for i in range(n-1,-1,-1):
...         A *= B_ext[i:i+n] #roll B with i-increment and multiply
...         A[n-1-i] += sum_arr #add sum to A at index
...     return A
```


```python
>>> N = 10000
>>> A = np.random.randint(0,255,(N))
>>> B = np.random.randint(0,255,(N))
>>> A_copy = A.copy()
>>> sum_arr = int(np.sum(B))
```


```python
>>> %timeit image_processing(A, B, sum_arr)
>>> %timeit pythran_image_processing(A_copy, B, sum_arr)
```

    60 ms ± 2.09 ms per loop (mean ± std. dev. of 7 runs, 10 loops each)
    51.7 ms ± 2.4 ms per loop (mean ± std. dev. of 7 runs, 10 loops each)


## Lorenz Attractor 

from <https://gist.github.com/dean-shaff/d1d0cdabf79e225ab96918b73916289f>. yet another kernel with loops, but sometimes that's the way the problem is naturally expressed. Note that Pythran does not support start arguments yet :-/


```python
>>> import numpy as np
>>> def rungekuttastep(h,y,fprime,*args):
...     k1 = h*fprime(y,*args)
...     k2 = h*fprime(y + 0.5*k1,*args)
...     k3 = h*fprime(y + 0.5*k2,*args)
...     k4 = h*fprime(y + k3,*args)
...     y_np1 = y + (1./6.)*k1 + (1./3.)*k2 + (1./3.)*k3 + (1./6.)*k4
...     return y_np1
... 
>>> def fprime_lorenz_numpy(y,*args):
...     sigma, rho, beta = args
...     yprime = np.zeros(y.shape[0])
...     yprime[0] = sigma*(y[1] - y[0])
...     yprime[1] = y[0]*(rho - y[2]) - y[1]
...     yprime[2] = y[0]*y[1] - beta*y[2]
...     return yprime
... 
>>> def attractor(n_iter, sigma, rho, beta):
...     y = np.arange(3)
...     for i in np.arange(n_iter):
...         y = rungekuttastep(0.001,y,fprime_lorenz_numpy,sigma, rho, beta)
...     return y
... 
```


```python
>>> %%pythran
>>> import numpy as np
>>> def rungekuttastep(h,y,fprime,sigma, rho, beta):
...     k1 = h*fprime(y,sigma, rho, beta)
...     k2 = h*fprime(y + 0.5*k1,sigma, rho, beta)
...     k3 = h*fprime(y + 0.5*k2,sigma, rho, beta)
...     k4 = h*fprime(y + k3,sigma, rho, beta)
...     y_np1 = y + (1./6.)*k1 + (1./3.)*k2 + (1./3.)*k3 + (1./6.)*k4
...     return y_np1
... 
>>> def fprime_lorenz_numpy(y,sigma, rho, beta):
...     yprime = np.zeros(y.shape[0])
...     yprime[0] = sigma*(y[1] - y[0])
...     yprime[1] = y[0]*(rho - y[2]) - y[1]
...     yprime[2] = y[0]*y[1] - beta*y[2]
...     return yprime
... 
>>> #pythran export pythran_attractor(int, float, float, float)
>>> def pythran_attractor(n_iter, sigma, rho, beta):
...     y = np.arange(3)
...     for i in np.arange(n_iter):
...         y = rungekuttastep(0.001,y,fprime_lorenz_numpy,sigma, rho, beta)
...     return y
```


```python
>>> %timeit attractor(1000, 10.,28.,8./3.)
>>> %timeit pythran_attractor(1000, 10.,28.,8./3.)
```

    17 ms ± 68.3 µs per loop (mean ± std. dev. of 7 runs, 100 loops each)
    682 µs ± 8.62 µs per loop (mean ± std. dev. of 7 runs, 1000 loops each)


Again, that's a lot of non-vectorized operation, not the best fit for numpy but that's okay for pythran. There's a function passed as a parameter of another function, but pythran can cope with that.
