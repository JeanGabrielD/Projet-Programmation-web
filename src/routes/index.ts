import { Router, Request, Response } from "express";

const router = Router();

// Page d'accueil
router.get("/", (req: Request, res: Response) => {
  res.send(`
    <h1>Accueil</h1>
    <nav>
      <a href="/nouvelle-seance">Nouvelle séance</a> |
      <a href="/seances-passees">Séances passées</a> |
      <a href="/statistiques">Statistiques</a>
    </nav>
  `);
});

// Nouvelle séance
router.get("/nouvelle-seance", (req: Request, res: Response) => {
  res.send("<h1>Nouvelle séance</h1>");
});

// Séances passées
router.get("/seances-passees", (req: Request, res: Response) => {
  res.send("<h1>Séances passées</h1>");
});

// Statistiques
router.get("/statistiques", (req: Request, res: Response) => {
  res.send("<h1>Statistiques</h1>");
});

export default router;
