import express from "express";
import statsHandler from "./api/index.js";
import topLangsHandler from "./api/top-langs.js";
import wakatimeHandler from "./api/wakatime.js";

const app = express();
const PORT = process.env.PORT || 9000;

// Helper para convertir handlers de Vercel a Express
const wrap = (handler) => async (req, res) => {
  try {
    await handler(req, res);
  } catch (err) {
    console.error(err);
    res.status(500).send("Internal Server Error");
  }
};

app.get("/api", wrap(statsHandler));
app.get("/api/index", wrap(statsHandler));
app.get("/api/top-langs", wrap(topLangsHandler));
app.get("/api/wakatime", wrap(wakatimeHandler));

app.get("/", (req, res) => {
  res.send("github-readme-stats running on Railway");
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
