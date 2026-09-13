FROM caddy:alpine
COPY index.html /srv/index.html
EXPOSE 8080
CMD ["caddy", "file-server", "--root", "/srv", "--listen", ":8080"]
