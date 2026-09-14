# syntax=docker/dockerfile:1.7
# Model Loader (github.com/scratchhax/model-loader, MIT) at a pinned commit, served by
# noevia behind its administrator login at /model-loader. Its browser libraries are
# bundled from checksummed downloads so no third-party script runs on noevia's origin.
FROM python:3.12-slim
ARG MODEL_LOADER_COMMIT=e11a6ec307fa405144678930d507046163369b46
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PIP_NO_CACHE_DIR=1
WORKDIR /srv
ADD https://github.com/scratchhax/model-loader.git#${MODEL_LOADER_COMMIT} /srv/upstream
RUN pip install -r /srv/upstream/requirements.txt \
 && cp -r /srv/upstream/app /srv/app && cp /srv/upstream/LICENSE /srv/LICENSE && rm -rf /srv/upstream
ADD --checksum=sha256:176e894661aa9cdc9a5cba6c720044cbbf7b8bd80d1c9a142a7c24b1b6c50d15 https://cdn.tailwindcss.com/3.4.17 /srv/vendor/tailwind.js
ADD --checksum=sha256:e209dda5c8235479f3166defc7750e1dbcd5a5c1808b7792fc2e6733768fb447 https://unpkg.com/htmx.org@2.0.4/dist/htmx.min.js /srv/vendor/htmx.min.js
ADD --checksum=sha256:b600e363d99d95444db54acbfb2deffec9ae792aa99a09229bcda078e5b55643 https://cdn.jsdelivr.net/npm/alpinejs@3.14.8/dist/cdn.min.js /srv/vendor/alpine.min.js
ADD --checksum=sha256:81ffafe13c37e1b25793b020d446f4d9739b949dadb7f9f79d709a0cad781c2f https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js /srv/vendor/chart.umd.min.js
COPY patch.py /srv/patch.py
RUN python /srv/patch.py && rm /srv/patch.py
EXPOSE 8090
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8090/palette.json',timeout=4)"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8090"]
