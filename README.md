# 🚢 Sistema de Gestão Portuária (SQL)

Este projeto consiste em um script SQL completo para simulação e gestão de um sistema logístico portuário. O banco de dados foi modelado para gerenciar portos, navios, atracações e cargas, com regras de negócio automatizadas.

## 🛠️ Tecnologias Utilizadas
* **PostgreSQL** (Sintaxe e PL/pgSQL)
* **DBeaver** (Gerenciamento e Testes)

## 🧠 Funcionalidades Inteligentes (Triggers)
1.  **Segurança de Atracação:** O sistema impede automaticamente (`RAISE EXCEPTION`) que um navio atraque em um cais com profundidade insuficiente para seu calado.
2.  **Automação de Cálculo:** Ao registrar a saída do navio, o sistema calcula automaticamente o tempo total de estadia e finaliza o status da operação.
3.  **Log de Auditoria:** Todas as cargas inseridas geram um log automático de segurança.

## 📊 Relatórios Gerados
O script final gera automaticamente:
* **Dashboard Operacional:** Status em tempo real dos berços de atracação (Livre/Ocupado).
* **Relatório Financeiro:** Soma do valor das cargas movimentadas agrupadas por Porto de Origem, formatado em moeda.

## 🚀 Como rodar
1.  Certifique-se de ter o PostgreSQL instalado.
2.  Execute o script `Trabalho_Final.sql` em sua ferramenta de preferência (pgAdmin/DBeaver).
3.  **Nota:** O script inicia com `DROP SCHEMA`, limpando o ambiente para uma execução limpa.
