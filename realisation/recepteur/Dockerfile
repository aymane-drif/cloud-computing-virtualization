FROM docker.io/library/python:3.12-slim
WORKDIR /app
COPY app.py .
RUN mkdir -p /var/log/recepteur
EXPOSE 8000
CMD ["python3", "-u", "app.py"]
