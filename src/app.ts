import express from "express";
import routes from "./routes";

const app = express();
const PORT = 3000;

// routes
app.use("/", routes);

app.listen(PORT, () => {
  console.log(`🚀 Serveur lancé sur http://localhost:${PORT}`);
});
