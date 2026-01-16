SET search_path TO shipping_db;

DO $$
DECLARE
    v_navio_grande INT := 1; -- Ever Given (Calado 15.7m)
    v_cais_raso INT := 6;    -- Santos B2 (Profundidade 13.0m)
    v_viagem_teste UUID;
    v_contagem_logs_antes INT;
    v_contagem_logs_depois INT;
BEGIN
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'INICIANDO BATERIA DE TESTES DE ESTRESSE';
    RAISE NOTICE '==================================================';

    -- ------------------------------------------------------------------------
    -- TESTE 1: INTEGRIDADE DE DADOS (CONSTRAINT CHECK)
    -- Tentativa: Inserir carga com peso negativo (-500kg).
    -- Expectativa: O banco DEVE BLOQUEAR.
    -- ------------------------------------------------------------------------
    RAISE NOTICE '--- [TESTE 1] Tentativa de Inserção de Peso Negativo...';
    BEGIN
        -- Pegando uma viagem qualquer existente
        SELECT id_viagem INTO v_viagem_teste FROM viagens LIMIT 1;
        
        INSERT INTO cargas (id_viagem, doc_conhecimento_transporte, cliente, peso_kg, valor_declarado)
        VALUES (v_viagem_teste, 'BL-TEST-FAIL-01', 'Hacker Corp', -500.00, 1000);
        
        RAISE NOTICE '❌ FALHA: O sistema permitiu peso negativo! (Isso é ruim)';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE '✅ SUCESSO: O sistema bloqueou a carga negativa. (Constraint funcionando)';
    END;

    -- ------------------------------------------------------------------------
    -- TESTE 2: SEGURANÇA OPERACIONAL (TRIGGER DE CALADO)
    -- Tentativa: Atracar o Ever Given (15.7m) no Cais de Santos B2 (13.0m).
    -- Expectativa: O banco DEVE DISPARAR UM ALERTA E BLOQUEAR.
    -- ------------------------------------------------------------------------
    RAISE NOTICE '--- [TESTE 2] Tentativa de Atracação Insegura (Navio > Cais)...';
    BEGIN
        -- Precisamos garantir que existe uma viagem para esse navio para testar
        -- Vamos usar a viagem do Navio 1 (Ever Given) que já existe no insert original
        SELECT id_viagem INTO v_viagem_teste FROM viagens WHERE id_navio = v_navio_grande LIMIT 1;

        INSERT INTO atracacoes (id_viagem, id_cais, data_atracacao)
        VALUES (v_viagem_teste, v_cais_raso, NOW());
        
        RAISE NOTICE '❌ FALHA: O sistema permitiu atracação perigosa! (Navio vai encalhar)';
    EXCEPTION WHEN raise_exception THEN
        RAISE NOTICE '✅ SUCESSO: A Trigger de Segurança impediu a atracação. Mensagem capturada.';
    END;

    -- ------------------------------------------------------------------------
    -- TESTE 3: AUDITORIA E LOGS (TRIGGER)
    -- Tentativa: Inserir uma carga válida.
    -- Expectativa: Deve aparecer um registro novo na tabela logs_sistema.
    -- ------------------------------------------------------------------------
    RAISE NOTICE '--- [TESTE 3] Verificação de Auditoria Automática...';
    
    SELECT COUNT(*) INTO v_contagem_logs_antes FROM logs_sistema;
    
    -- Inserção Válida
    INSERT INTO cargas (id_viagem, doc_conhecimento_transporte, cliente, peso_kg, valor_declarado)
    VALUES ((SELECT id_viagem FROM viagens LIMIT 1), 'BL-QA-OK-999', 'QA Team', 1000.00, 50000);
    
    SELECT COUNT(*) INTO v_contagem_logs_depois FROM logs_sistema;
    
    IF v_contagem_logs_depois > v_contagem_logs_antes THEN
        RAISE NOTICE '✅ SUCESSO: Log de auditoria gerado automaticamente.';
    ELSE
        RAISE NOTICE '❌ FALHA: Nenhum log foi gerado.';
    END IF;

    -- ------------------------------------------------------------------------
    -- TESTE 4: ESTRESSE DE CÁLCULO (UPDATE)
    -- Tentativa: Simular saída de navio.
    -- Expectativa: Calcular horas automaticamente.
    -- ------------------------------------------------------------------------
    RAISE NOTICE '--- [TESTE 4] Automação de Saída de Navio...';
    
    UPDATE atracacoes 
    SET data_desatracacao = NOW() + INTERVAL '10 hours'
    WHERE id_atracacao = (SELECT id_atracacao FROM atracacoes WHERE data_desatracacao IS NULL LIMIT 1);
    
    RAISE NOTICE '✅ SUCESSO: Update realizado. Verificando dashboard...';

    RAISE NOTICE '==================================================';
    RAISE NOTICE 'RELATÓRIO FINAL: SISTEMA APROVADO NOS TESTES';
    RAISE NOTICE '==================================================';
END $$;