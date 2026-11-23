# DB-017: Consultas Lentas — Medição e Correção

## 1. Decisões Arquiteturais e Alinhamentos

- **Consultas candidatas:** a QA-024 não foi fornecida. As consultas foram derivadas dos acessos descritos no Caderno; portanto, ainda falta confirmar se correspondem às consultas observadas em QA.
- **Q1 — listagem pública:** para projetos publicados e públicos, ordenados por título e paginados com `LIMIT 20`, a V0017 cria o índice parcial `idx_project_public_title` em `academic_pi.project (title) WHERE is_public AND status = 'published'`.
- **Q1 sem paginação:** a consulta completa não mostrou ganho que justificasse o índice. A decisão se aplica à listagem paginada por título.
- **Q2, Q3 e Q4:** não receberam índices novos. As medições indicaram uso dos índices existentes.
- **Q5 — períodos abertos:** o índice candidato em `(closes_at, opens_at)` foi testado e descartado. O ganho ficou dentro do ruído, o índice ocupava 432 kB e a consulta continuava lendo `project`.
- **Dados públicos:** o índice mantido usa apenas `title` e o predicado público `is_public AND status = 'published'`. Não inclui CPF, e-mail, notas, horas ou arquivos.

## 2. Matriz de Regras e Como o Banco as Atende

| Regra | Caderno | Banco e evidência |
| :--- | :--- | :--- |
| Listagem pública de projetos publicados, ordenada por título e paginada | 29 e 35 | `idx_project_public_title`; Q1 paginada caiu de 2,004 ms para 0,056 ms na revalidação pareada |
| Participações ativas de um aluno | 31 e 32 | Índice existente em `project_participation.student_id`; sem mudança |
| Solicitações pendentes de um projeto | 30 e 31 | Índice único existente em `(project_id, student_id)`; sem mudança |
| Projetos de docente com período aberto | 31 e 36 | Índices existentes em `project_instructor` e `enrollment_period`; sem mudança |
| Nenhum índice com dados privados apenas para acelerar consulta pública | Critério da issue | Índice novo contém somente título e predicado público |
| Registrar custo de escrita e armazenamento | Critério da issue | Espaço, criação e custo de escrita documentados em `evidence/DB-017-query-performance.md` |
| Não declarar desempenho de produção a partir de medição local | Critério da issue | Medições feitas localmente em Docker; ambiente e limitações registrados em `evidence/DB-017-query-performance.md` |

Na revalidação da Q1 paginada, sem o índice o plano usou `Seq Scan` e `top-N heapsort`; com a V0017, usou `Index Scan` em `idx_project_public_title`. A comparação foi feita com a mesma carga sintética de estresse.

## 3. Limitações e Follow-ups

- O ganho da V0017 depende da listagem ordenar por título e usar paginação. Outras ordenações podem não usar esse índice.
- A proporção de projetos públicos foi assumida em 10%. Uma proporção maior pode reduzir a vantagem do índice parcial.
- As medições foram feitas em uma máquina local, com Docker e cache quente. Não representam desempenho de produção.
- Arquivos em `assets.project_file` não foram medidos; a carga não gerou arquivos.
- A relação entre as consultas candidatas e as consultas observadas em QA-024 continua pendente de confirmação.
- Para Q5, um índice de intervalo com `tstzrange` e GiST pode ser avaliado futuramente; a mudança de esquema e consulta ficou fora desta issue.

## 4. Evidências e Validação

- Relatório detalhado: `evidence/DB-017-query-performance.md`
- Consultas: `evidence/DB-017-queries.sql`
- Planos pareados da Q1: `evidence/DB-017-queries-antes-v0017.txt` e `evidence/DB-017-queries-apos-v0017.txt`
- Carga sintética: `evidence/DB-017-load.sql`
- Custo de escrita: `evidence/DB-017-write-cost.sql`
- Migration: `migrations/V0017__add_public_project_title_index.sql`
- `scripts/validate.sh` e `scripts/validate_upgrade.sh` concluíram com sucesso; a validação de upgrade não detectou drift.