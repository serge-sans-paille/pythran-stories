{% extends 'markdown.tpl' %}

{% block input %}
```{% if nb.metadata.language_info %}{{ nb.metadata.language_info.name }}{% endif %}
{%- for line in cell.source.split('\n') %}
{%- if line.startswith(' ') or not line%}
... {{line}}
{%- else %}
>>> {{line}}
{%- endif %}
{%- endfor %}
```
{% endblock input %}
