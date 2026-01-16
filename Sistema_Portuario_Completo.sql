-- ============================================================================
-- CONTEÚDO:
-- 1. Estrutura (Tabelas e Tipos)
-- 2. Inteligência (Triggers e Automação)
-- 3. Carga de Dados e Operação
-- 4. Validação de Regras de Negócio
-- 5. Relatórios Gerenciais (Financeiro e Operacional)
-- ============================================================================

-- ============================================================================
-- 1. CONFIGURAÇÃO E LIMPEZA (RESET TOTAL)
-- ============================================================================
DROP SCHEMA IF EXISTS shipping_db CASCADE;
CREATE SCHEMA shipping_db;
SET search_path TO shipping_db;
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 2. CRIAÇÃO DA ESTRUTURA
-- ============================================================================

-- Tipos (Enums)
CREATE TYPE status_navio_enum AS ENUM ('AGUARDANDO', 'EM_TRANSITO', 'EM_OPERACAO', 'MANUTENCAO');
CREATE TYPE categoria_carga_enum AS ENUM ('GERAL', 'PERIGOSA', 'REFRIGERADA', 'GRANEL_SOLIDO', 'GRANEL_LIQUIDO');

-- Tabelas
CREATE TABLE portos (
    id_porto INT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    codigo_un CHAR(5) UNIQUE NOT NULL,
    pais VARCHAR(50) NOT NULL,
    cidade VARCHAR(100),
    capacidade_patio_teu INT
);

CREATE TABLE cais (
    id_cais INT PRIMARY KEY,
    id_porto INT REFERENCES portos(id_porto),
    numero_berco VARCHAR(10) NOT NULL,
    profundidade_metros DECIMAL(4,2) NOT NULL,
    equipamento_guindaste BOOLEAN DEFAULT TRUE,
    CONSTRAINT uq_cais_porto UNIQUE (id_porto, numero_berco)
);

CREATE TABLE navios (
    id_navio INT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    imo_number CHAR(7) UNIQUE NOT NULL,
    registro_naval_doc VARCHAR(50) UNIQUE NOT NULL,
    bandeira VARCHAR(50),
    capacidade_teu INT NOT NULL,
    calado_maximo DECIMAL(4,2) NOT NULL,
    status status_navio_enum DEFAULT 'AGUARDANDO',
    detalhes_tecnicos JSONB
);

CREATE TABLE viagens (
    id_viagem UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    id_navio INT REFERENCES navios(id_navio),
    id_porto_origem INT REFERENCES portos(id_porto),
    id_porto_destino INT REFERENCES portos(id_porto),
    data_saida_prevista TIMESTAMP WITH TIME ZONE,
    data_chegada_estimada TIMESTAMP WITH TIME ZONE,
    manifesto_carga_doc VARCHAR(50) UNIQUE,
    status_viagem VARCHAR(20) DEFAULT 'PROGRAMADA'
);

CREATE TABLE atracacoes (
    id_atracacao BIGSERIAL PRIMARY KEY,
    id_viagem UUID REFERENCES viagens(id_viagem),
    id_cais INT REFERENCES cais(id_cais),
    data_atracacao TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    data_desatracacao TIMESTAMP WITH TIME ZONE,
    tempo_atracado_horas DECIMAL(10,2),
    status_operacao VARCHAR(20) DEFAULT 'OPERANDO'
);

CREATE TABLE cargas (
    id_carga BIGSERIAL PRIMARY KEY,
    id_viagem UUID REFERENCES viagens(id_viagem),
    doc_conhecimento_transporte VARCHAR(50) NOT NULL UNIQUE,
    cliente VARCHAR(100) NOT NULL,
    peso_kg DECIMAL(10,2) NOT NULL,
    quantidade_teu INT DEFAULT 1,
    categoria categoria_carga_enum DEFAULT 'GERAL',
    valor_declarado NUMERIC(15, 2),
    data_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE logs_sistema (
    id_log SERIAL PRIMARY KEY,
    tabela_afetada VARCHAR(50),
    acao VARCHAR(50),
    usuario VARCHAR(50),
    detalhes JSONB,
    data_log TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 3. TRIGGERS (INTELIGÊNCIA)
-- ============================================================================

-- 3.1 Trigger de Segurança (Impede navio grande em cais raso)
CREATE OR REPLACE FUNCTION func_valida_calado()
RETURNS TRIGGER AS $$
DECLARE
    v_profundidade_cais DECIMAL;
    v_calado_navio DECIMAL;
BEGIN
    SELECT profundidade_metros INTO v_profundidade_cais FROM cais WHERE id_cais = NEW.id_cais;
    SELECT n.calado_maximo INTO v_calado_navio 
    FROM navios n JOIN viagens v ON n.id_navio = v.id_navio 
    WHERE v.id_viagem = NEW.id_viagem;

    IF v_calado_navio > v_profundidade_cais THEN
        RAISE EXCEPTION 'ALERTA DE SEGURANÇA: Calado do Navio (%m) maior que Cais (%m)', v_calado_navio, v_profundidade_cais;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_seguranca_atracacao BEFORE INSERT ON atracacoes
FOR EACH ROW EXECUTE FUNCTION func_valida_calado();

-- 3.2 Trigger de Automação (Calcula tempo de estadia ao sair)
CREATE OR REPLACE FUNCTION func_calc_tempo_atracado()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.data_desatracacao IS NOT NULL THEN
        NEW.tempo_atracado_horas := EXTRACT(EPOCH FROM (NEW.data_desatracacao - NEW.data_atracacao)) / 3600;
        NEW.status_operacao := 'FINALIZADA';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_atracacao_tempo BEFORE UPDATE ON atracacoes
FOR EACH ROW WHEN (OLD.data_desatracacao IS DISTINCT FROM NEW.data_desatracacao)
EXECUTE FUNCTION func_calc_tempo_atracado();

-- 3.3 Trigger de Auditoria (Logs automáticos)
CREATE OR REPLACE FUNCTION func_audit_geral()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO logs_sistema (tabela_afetada, acao, usuario, detalhes)
    VALUES (TG_TABLE_NAME, TG_OP, current_user, jsonb_build_object('doc', NEW.doc_conhecimento_transporte));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_cargas AFTER INSERT ON cargas
FOR EACH ROW EXECUTE FUNCTION func_audit_geral();

-- ============================================================================
-- 4. CARGA DE DADOS (INSERTS)
-- ============================================================================

INSERT INTO portos (id_porto, nome, codigo_un, pais, cidade, capacidade_patio_teu) VALUES
(1, 'Port of Jebel Ali', 'AEJEA', 'Emirados Arabes', 'Dubai', 19300000), 
(2, 'Port of Shanghai', 'CNSHA', 'China', 'Shanghai', 43500000),
(3, 'Port of Singapore', 'SGSIN', 'Singapura', 'Singapore', 37200000),
(4, 'Port of Ningbo', 'CNNGB', 'China', 'Ningbo', 28700000),
(5, 'Port of Shenzhen', 'CNSZN', 'China', 'Shenzhen', 26550000),
(6, 'Port of Busan', 'KRPUS', 'Coreia do Sul', 'Busan', 21990000),
(7, 'Port of Qingdao', 'CNQGD', 'China', 'Qingdao', 21000000),
(8, 'Port of Hong Kong', 'HKHKG', 'Hong Kong', 'Hong Kong', 18300000),
(9, 'Port of Rotterdam', 'NLRTM', 'Holanda', 'Rotterdam', 14350000),
(10, 'Port of Antwerp', 'BEANR', 'Belgica', 'Antwerp', 12000000),
(11, 'Port Klang', 'MYPKG', 'Malasia', 'Klang', 13500000),
(12, 'Port of Los Angeles', 'USLAX', 'EUA', 'Los Angeles', 9300000),
(13, 'Port of Hamburg', 'DEHAM', 'Alemanha', 'Hamburg', 8500000),
(14, 'Port of Tanjung', 'MYTPP', 'Malasia', 'Johor', 9800000),
(15, 'Laem Chabang', 'THLCH', 'Tailandia', 'Chonburi', 8000000),
(16, 'Port of New York', 'USNYC', 'EUA', 'New York', 7500000),
(17, 'Porto de Santos', 'BRSSZ', 'Brasil', 'Santos', 4200000),
(18, 'Port of Valencia', 'ESVLC', 'Espanha', 'Valencia', 5400000),
(19, 'Port of Tokyo', 'JPTYO', 'Japao', 'Tokyo', 4800000),
(20, 'Port of Vancouver', 'CAVAN', 'Canada', 'Vancouver', 3400000);

INSERT INTO cais (id_cais, id_porto, numero_berco, profundidade_metros) VALUES
(1, 1, 'JBL-01', 17.00),
(2, 1, 'JBL-02', 16.50),
(3, 9, 'ROT-A1', 18.00),
(4, 9, 'ROT-A2', 15.00),
(5, 17, 'STS-B1', 14.50),
(6, 17, 'STS-B2', 13.00),
(7, 2, 'SHA-X1', 16.00),
(8, 2, 'SHA-X2', 16.00);

INSERT INTO navios (id_navio, nome, imo_number, registro_naval_doc, bandeira, capacidade_teu, calado_maximo, detalhes_tecnicos) VALUES
(1, 'Ever Given', '9811000', 'PAN-2018-883', 'Panama', 20124, 15.7, '{"comprimento": 400}'),
(2, 'Maersk Madrid', '9778791', 'DNK-2017-112', 'Dinamarca', 20568, 16.0, '{"comprimento": 399}'),
(3, 'MSC Gülsün', '9839430', 'PAN-2019-555', 'Panama', 23756, 16.5, '{"motor": "Hibrido"}'),
(4, 'HMM Algeciras', '9863297', 'PAN-2020-999', 'Panama', 23964, 16.5, NULL),
(5, 'CMA CGM Jacques', '9776418', 'FRA-2020-001', 'Franca', 23000, 16.0, '{"propulsao": "LNG"}'),
(6, 'COSCO Shipping', '9795610', 'HKG-2018-777', 'Hong Kong', 21237, 14.5, NULL),
(7, 'OOCL Germany', '9776183', 'HKG-2017-222', 'Hong Kong', 21413, 15.5, NULL),
(8, 'ONE Apus', '9806079', 'JPN-2019-333', 'Japao', 14000, 14.0, NULL),
(9, 'Wan Hai 313', '9200001', 'SIN-2021-123', 'Singapura', 3000, 10.5, NULL),
(10, 'Log-In Jacarandá', '9600001', 'BRA-2012-555', 'Brasil', 2800, 9.5, NULL),
(11, 'ZIM Kingston', '9389693', 'MLT-2008-099', 'Malta', 4500, 11.0, NULL),
(12, 'Hapag-Lloyd Berlin', '9708000', 'DEU-2014-888', 'Alemanha', 15000, 15.0, NULL),
(13, 'Ever Ace', '9893890', 'TWN-2021-444', 'Taiwan', 23992, 16.5, NULL),
(14, 'Seaspan Amazon', '9600002', 'HKG-2015-666', 'Hong Kong', 10000, 13.0, NULL),
(15, 'Cap San Nicolas', '9622222', 'DEU-2013-111', 'Alemanha', 9600, 12.5, NULL);

INSERT INTO viagens (id_navio, id_porto_origem, id_porto_destino, manifesto_carga_doc, data_saida_prevista) VALUES
(1, 1, 9, 'MNF-23-001', NOW() - INTERVAL '15 days'),
(3, 2, 12, 'MNF-23-002', NOW() - INTERVAL '10 days'),
(10, 17, 9, 'MNF-23-003', NOW() - INTERVAL '5 days'),
(5, 3, 1, 'MNF-23-004', NOW() - INTERVAL '20 days'),
(2, 4, 13, 'MNF-23-005', NOW() - INTERVAL '8 days'),
(8, 7, 17, 'MNF-23-006', NOW() - INTERVAL '30 days'),
(4, 9, 2, 'MNF-23-007', NOW() - INTERVAL '2 days'),
(6, 10, 5, 'MNF-23-008', NOW() - INTERVAL '12 days'),
(7, 1, 3, 'MNF-23-009', NOW() - INTERVAL '1 day'),
(9, 6, 8, 'MNF-23-010', NOW() - INTERVAL '25 days'),
(11, 12, 1, 'MNF-23-011', NOW() - INTERVAL '3 days'),
(12, 13, 2, 'MNF-23-012', NOW() - INTERVAL '6 days'),
(13, 2, 9, 'MNF-23-013', NOW() - INTERVAL '9 days'),
(14, 9, 17, 'MNF-23-014', NOW() - INTERVAL '4 days'),
(15, 17, 1, 'MNF-23-015', NOW() - INTERVAL '11 days');

INSERT INTO cargas (id_viagem, doc_conhecimento_transporte, cliente, peso_kg, quantidade_teu, categoria, valor_declarado) VALUES
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-001'), 'BL-DUB-001', 'Samsung UAE', 15000, 2, 'GERAL', 500000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-001'), 'BL-DUB-002', 'Emirates Alum', 40000, 4, 'GERAL', 120000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-003'), 'BL-BRA-555', 'JBS Foods', 28000, 2, 'REFRIGERADA', 300000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-003'), 'BL-BRA-556', 'Vale Rio', 50000, 5, 'GRANEL_SOLIDO', 80000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-002'), 'BL-CHI-999', 'Xiaomi Tech', 5000, 1, 'GERAL', 200000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-004'), 'BL-SIN-111', 'Petronas', 45000, 1, 'PERIGOSA', 450000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-005'), 'BL-NGB-222', 'Adidas', 3000, 1, 'GERAL', 150000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-006'), 'BL-BUS-333', 'Hyundai Motors', 12000, 3, 'GERAL', 900000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-007'), 'BL-ROT-444', 'Heineken', 22000, 2, 'GERAL', 80000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-008'), 'BL-ANT-555', 'Bayer', 8000, 1, 'PERIGOSA', 600000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-009'), 'BL-JEB-666', 'Dubai Constr', 60000, 6, 'GRANEL_SOLIDO', 40000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-010'), 'BL-QIN-777', 'Tsingtao', 18000, 2, 'GRANEL_LIQUIDO', 55000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-011'), 'BL-LAX-888', 'Tesla', 5000, 2, 'PERIGOSA', 1200000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-012'), 'BL-HAM-000', 'Siemens', 9500, 1, 'GERAL', 350000),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-013'), 'BL-SHA-101', 'Foxconn', 7000, 1, 'GERAL', 400000);

-- Atracações iniciais
INSERT INTO atracacoes (id_viagem, id_cais, data_atracacao, data_desatracacao) VALUES
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-001'), 1, NOW() - INTERVAL '16 days', NOW() - INTERVAL '15 days'),
((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-003'), 5, NOW(), NULL);

-- ============================================================================
-- 5. TESTES E VALIDAÇÕES
-- ============================================================================

-- TESTE 1: TENTATIVA DE ATRACAÇÃO PERIGOSA (TRIGGER DE SEGURANÇA)
-- O comando abaixo está comentado para não gerar erro na execução automática.
-- Para provar que o sistema bloqueia, remova os '--' da linha abaixo:

-- INSERT INTO atracacoes (id_viagem, id_cais, data_atracacao) VALUES ((SELECT id_viagem FROM viagens WHERE manifesto_carga_doc = 'MNF-23-013'), 6, NOW());


-- TESTE 2: AUTOMAÇÃO DE SAÍDA (TRIGGER DE CÁLCULO DE TEMPO)
-- O navio Log-In Jacarandá sai do cais 5 agora. O sistema deve calcular o tempo sozinho.
UPDATE atracacoes 
SET data_desatracacao = NOW() 
WHERE id_cais = 5 AND data_desatracacao IS NULL;

-- ============================================================================
-- 6. RELATÓRIOS FINAIS
-- ============================================================================

-- View (Dashboard) - Com DROP para evitar erro de substituição
DROP VIEW IF EXISTS vw_dashboard_operacional CASCADE;

CREATE VIEW vw_dashboard_operacional AS
SELECT 
    p.nome AS porto,
    c.numero_berco,
    n.nome AS navio,
    v.manifesto_carga_doc,
    CASE WHEN a.data_desatracacao IS NULL THEN 'OCUPADO' ELSE 'LIVRE' END AS status_cais,
    COALESCE(a.tempo_atracado_horas, EXTRACT(EPOCH FROM (NOW() - a.data_atracacao))/3600) AS horas_no_cais,
    a.status_operacao
FROM atracacoes a
JOIN cais c ON a.id_cais = c.id_cais
JOIN portos p ON c.id_porto = p.id_porto
JOIN viagens v ON a.id_viagem = v.id_viagem
JOIN navios n ON v.id_navio = n.id_navio;

-- EXIBIÇÃO AUTOMÁTICA DOS RESULTADOS

SELECT '--- [1] DASHBOARD OPERACIONAL ---' as relatorio_info;
SELECT * FROM vw_dashboard_operacional;

SELECT '--- [2] RANKING FINANCEIRO POR PORTO ---' as relatorio_info;
SELECT 
    p.nome AS porto_origem,
    COUNT(c.id_carga) AS qtd_containers,
    TO_CHAR(SUM(c.valor_declarado), 'L999G999G999D99') AS valor_total_movimentado
FROM cargas c
JOIN viagens v ON c.id_viagem = v.id_viagem
JOIN portos p ON v.id_porto_origem = p.id_porto
GROUP BY p.nome
ORDER BY SUM(c.valor_declarado) DESC;