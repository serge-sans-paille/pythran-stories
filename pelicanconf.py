#!/usr/bin/env python
# -*- coding: utf-8 -*- #
from __future__ import unicode_literals
import glob, os

AUTHOR = 'serge-sans-paille and other pythraners'
SITENAME = 'Pythran stories'
SITEURL = 'http://serge-sans-paille.github.io/pythran-stories'

PATH = 'content'
STATIC_PATHS = ['notebooks', 'images'] + [os.path.basename(p) for p in glob.glob(os.path.join(PATH, "*_files"))]

TIMEZONE = 'Europe/Paris'

DEFAULT_LANG = 'en'

# Feed generation is usually not desired when developing
FEED_ALL_ATOM = None
CATEGORY_FEED_ATOM = None
TRANSLATION_FEED_ATOM = None
AUTHOR_FEED_ATOM = None
AUTHOR_FEED_RSS = None

# Blogroll
LINKS = (('Pythran Doc', 'http://pythonhosted.org/pythran'),
         ('Pythran on PyPI', 'https://pypi.python.org/pypi/pythran'),
        )

# Social widget
SOCIAL = (('github', 'https://github.com/serge-sans-paille/pythran'),
        )

DEFAULT_PAGINATION = 10
RELATIVE_URLS = True
DELETE_OUTPUT_DIRECTORY = True

THEME= 'bootstrap2'
