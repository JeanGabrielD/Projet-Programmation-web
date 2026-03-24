"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const dotenv_1 = __importDefault(require("dotenv"));
const database_1 = require("./db/database");
const auth_1 = __importDefault(require("./routes/auth"));
const sessions_1 = __importDefault(require("./routes/sessions"));
dotenv_1.default.config();
const app = (0, express_1.default)();
const PORT = process.env.PORT || 3001;
// En prod, FRONTEND_URL peut contenir plusieurs origines séparées par des virgules
// ex: https://d1234abcd.cloudfront.net,https://mondomaine.com
const allowedOrigins = (process.env.FRONTEND_URL || 'http://localhost:5173').split(',');
app.use((0, cors_1.default)({
    origin: (origin, callback) => {
        if (!origin || allowedOrigins.includes(origin))
            callback(null, true);
        else
            callback(new Error('CORS bloque cette origine : ' + origin));
    },
    credentials: true,
}));
app.use(express_1.default.json());
app.use('/api/auth', auth_1.default);
app.use('/api/sessions', sessions_1.default);
app.get('/api/health', (_, res) => res.json({ status: 'ok' }));
async function start() {
    await (0, database_1.initDatabase)();
    app.listen(PORT, () => {
        console.log('Backend running on port ' + PORT);
    });
}
start().catch(console.error);
