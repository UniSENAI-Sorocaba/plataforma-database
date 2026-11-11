# DB-012: Períodos de Inscrição e Inscrições (Janela, Status e Unicidade)

## 1. Decisões Arquiteturais e Alinhamentos
- **Reconciliação de escopo**: esta entrega não cria estrutura nova. A estrutura vem da `V0008` (DB-008); a DB-012 confere e documenta janela, status e unicidade, com evidência em `evidence/DB-012-integrity.md`.
- **Terminologia do Caderno**: usa-se *período de inscrição* (`academic_pi.enrollment_period`) e *inscrição/participação* (`academic_pi.project_participation`). Um *aviso* é um comunicado (geral ou de um projeto, item 34) e não é tratado como edital.
- **Fluxo de solicitação**: o aluno solicita participação no período de inscrição e o docente aprova ou nega (item 31). Não há convite individual, nem status de convite no domínio.
- **Datas em UTC, leitura em UTC-3**: `opens_at` e `closes_at` são `timestamptz`. A interpretação em UTC-3 (Brasília, item 36) é feita na apresentação.
- **Status do período derivado**: o período não tem coluna de status. Futuro, aberto e encerrado são calculados a partir das datas, porque uma constraint não pode depender de `now()`.
- **Conflito entre os itens 61 e 62 do Caderno**: o item 61 define prazos não prorrogáveis e o item 62 permite que o docente responsável ajuste o prazo. **Não há interpretação escolhida e o conflito não está resolvido.** O banco só exige uma janela coerente e aceita a alteração das datas.

## 2. Matriz de Regras e Como o Banco as Atende
| Regra | Item do Caderno | Banco |
|---|---|---|
| Janela com fechamento não anterior à abertura | 31, 36 | `enrollment_period_window_ck` (`closes_at >= opens_at`) |
| Datas em UTC-3 | 36 | `timestamptz`; conversão na apresentação |
| Status da inscrição: `requested`, `approved`, `denied`, `withdrawn`, `removed` | 31, 37 | `project_participation_status_ck` |
| Um registro por aluno em cada projeto | 31 | `project_participation_project_student_unq` |
| Um PI e uma Extensão ativos por aluno; projeto nas duas categorias ocupa as duas vagas | 32 | `idx_project_participation_student_active_pi` e `idx_project_participation_student_active_extension` (únicos parciais) |
| Depois de aprovado, só o docente altera a participação | 37 | Aplicação e RBAC (fora do banco) |
| Prazo não prorrogável / docente ajusta o prazo | 61 / 62 | Não imposto pelo banco; conflito em aberto |

## 3. Limitações e Follow-ups
- A inscrição não referencia o período de inscrição: o banco não garante que ela foi feita dentro da janela, e a unicidade atual é por projeto, não por período.
- Nada impede períodos de inscrição sobrepostos no mesmo projeto.
- O check da janela usa `>=`, então uma janela de duração zero é aceita. Trocar para `>` exige migration nova.
- A confirmação de que "status" no escopo significa status da inscrição mais status do período derivado das datas está pendente.
- O conflito R61/R62 depende de decisão do PO. Até lá, quem pode alterar o prazo não é regra do banco.
- As SPECs de AUTH e PI constam como Draft; as decisões acima aguardam aprovação conforme o fluxo de governança.