"""Replace this starter during Section 2."""

from fastapi import FastAPI

app = FastAPI()


@app.get("/")
def home():
    return "REPLACE ME WITH YOUR NAME"


@app.get("/api/me")
def me():
    return {
        "name": "REPLACE ME WITH YOUR NAME",
        "student_id": "REPLACE ME WITH YOUR STUDENT ID",
    }
