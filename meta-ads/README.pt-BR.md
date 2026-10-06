# Meta Ads

Opere anúncios do Facebook e do Instagram por um agente do Pepe: leia contas, campanhas, conjuntos, anúncios e resultados, pesquise públicos, e monte, edite, pause, duplique e (se você permitir) ligue campanhas. Usa a API de Marketing oficial da Meta.

```bash
pepe plugin install @jhonathas/meta-ads
```

## Ferramentas

**Leitura (não muda nada)**

| Ferramenta | O que faz |
|---|---|
| `meta_ads_accounts` | Lista suas contas de anúncio com status, moeda e gasto total |
| `meta_ads_campaigns`, `meta_ads_adsets`, `meta_ads_ads` | Listam com status, orçamento, público e, nos anúncios, por que a Meta reprovou |
| `meta_ads_insights` | Resultados de um período: gasto, alcance, cliques, CTR, CPC, CPM, resultados por ação, ROAS. Por conta, campanha, conjunto ou anúncio; separados por idade, gênero, país, posicionamento e mais; por dia, semana ou mês |
| `meta_ads_get` | Tudo sobre uma campanha, conjunto ou anúncio |
| `meta_ads_search_targeting` | Acha interesses, comportamentos, locais e mais, com os ids para usar num conjunto |
| `meta_ads_estimate` | Estima quantas pessoas um público alcança antes de você montá-lo |
| `meta_ads_audiences`, `meta_ads_pixels`, `meta_ads_pages` | Públicos personalizados, pixels, Páginas do Facebook e contas do Instagram ligadas |
| `meta_ads_preview` | Um link que mostra como o anúncio fica |

**Criação (tudo nasce PAUSADO)**

| Ferramenta | O que faz |
|---|---|
| `meta_ads_create_draft` | Tudo numa chamada: campanha, conjunto, criativo e anúncio, com um link para revisar. Se uma etapa falha, o que foi criado antes é apagado |
| `meta_ads_create_campaign`, `meta_ads_create_adset`, `meta_ads_create_creative`, `meta_ads_create_ad` | As mesmas etapas, uma a uma, para controle total (público, posicionamentos, agenda, lance, link, vídeo, carrossel ou um post existente) |
| `meta_ads_upload_video` | Adiciona um vídeo a partir de um endereço `https://` público |
| `meta_ads_create_lookalike` | Um público semelhante a partir de um existente |

**Alteração**

| Ferramenta | O que faz |
|---|---|
| `meta_ads_update` | Renomeia, muda orçamento, agenda, público ou o criativo de um anúncio |
| `meta_ads_set_status` | Pausa, arquiva, apaga ou LIGA |
| `meta_ads_duplicate` | Copia uma campanha, conjunto ou anúncio (a cópia fica PAUSADA) |

## O que você precisa antes de começar

- Um **portfólio empresarial da Meta** (Business Manager, <https://business.facebook.com>) dono da sua **conta de anúncio** e da sua **Página do Facebook**, ou com acesso a elas. A conta de anúncio precisa de uma forma de pagamento funcionando antes de qualquer coisa rodar.
- Uma conta de **desenvolvedor da Meta** (<https://developers.facebook.com>) e um **app** nela.
- Opcional: a conta do **Instagram** ligada à Página, se os anúncios também devem sair com esse perfil.

## Configure (uns 20 a 30 minutos, uma vez)

A Meta muda as telas e os nomes das permissões com frequência. Use estes passos como um mapa e confira na documentação da API de Marketing da própria Meta (<https://developers.facebook.com/docs/marketing-api/get-started>).

1. **Crie um app.** Em <https://developers.facebook.com/apps> escolha **Criar app**, selecione o caso de uso de **publicidade e promoção** (ou o tipo Business), ligue ao seu portfólio empresarial e adicione o produto **API de Marketing**.
2. **Crie um Usuário do sistema.** Em **Configurações do negócio → Usuários → Usuários do sistema**, adicione um (com a função **Administrador**). É uma conta robô: o token dele não expira e não depende de uma pessoa continuar logada.
3. **Dê os ativos a ele.** Selecione o Usuário do sistema, escolha **Adicionar ativos** e atribua a sua **conta de anúncio** (controle total) e a sua **Página do Facebook**. Sem a Página, criar anúncios falha.
4. **Gere o token.** No Usuário do sistema escolha **Gerar novo token**, selecione o seu app e marque **`ads_read`** e **`ads_management`**. Copie o token na hora: a Meta mostra uma única vez. Para só ler, `ads_read` basta.
5. **Ache o id da conta de anúncio.** No Gerenciador de Anúncios abra **Configurações**: o número em *Visão geral da conta* é ele. Use só os dígitos (por exemplo `1234567890`), sem o prefixo `act_`.
6. **Preencha o plugin.** No painel do Pepe abra **Plugins**, ache **meta-ads** e escolha **Configure**:

   | Campo | O que colocar |
   |---|---|
   | Access token | O token, escrito como `${META_ADS_ACCESS_TOKEN}` com o valor real no ambiente do servidor do Pepe, para nunca ficar no arquivo de configurações |
   | Ad account id | O número do passo 5. Opcional, mas evita repetir |
   | Facebook Page id | Deixe vazio por enquanto (veja o passo 8) |
   | Instagram account id | Deixe vazio por enquanto (veja o passo 8) |
   | Allow creating | `no` (padrão) é só leitura. `yes` deixa o agente criar e alterar, sempre PAUSADO |
   | Highest daily budget | O máximo de um orçamento diário, em unidades inteiras como `50`. Obrigatório para gravar qualquer orçamento. Um orçamento total pode ser no máximo isso vezes os dias |
   | Allow turning on | `no` (padrão): o agente nunca começa a gastar. `yes` deixa ligar o que tem orçamento dentro do limite |
   | Graph API version | Opcional, como `v23.0` |

   As mesmas configurações podem vir do ambiente: `META_ADS_ACCESS_TOKEN`, `META_ADS_ACCOUNT_ID`, `META_ADS_MAX_DAILY_BUDGET` e as demais no mesmo estilo.
7. **Dê as ferramentas a um agente, começando pela leitura:**

   ```bash
   pepe agent tools my-agent --add meta_ads_accounts,meta_ads_pages,meta_ads_campaigns,meta_ads_adsets,meta_ads_ads,meta_ads_insights
   ```

   Pergunte: *"liste minhas contas de anúncio"* e *"como foram minhas campanhas nos últimos 7 dias?"*
8. **Deixe o plugin achar os ids da Página e do Instagram.** Peça ao agente: *"mostre minhas Páginas e contas do Instagram"* (`meta_ads_pages`). Copie o id da Página, e o do Instagram do perfil que quiser, para os dois campos vazios do passo 6.
9. **Só então ligue a escrita.** Ponha *Allow creating* em `yes`, defina um *Highest daily budget* pequeno, adicione as ferramentas de criação ao agente e peça um rascunho. Ele nasce PAUSADO: abra o link que ele devolve no Gerenciador de Anúncios e revise. Só ponha *Allow turning on* em `yes` quando confiar no fluxo; até lá você liga os rascunhos sozinho no Gerenciador.

Se algo estiver errado a ferramenta diz o quê: o token expirou ou falta uma permissão, a Página ou a conta de anúncio não foi atribuída ao Usuário do sistema, a conta não tem forma de pagamento, ou a Meta recusou o anúncio (a mensagem dela é repassada).

## Segurança (este plugin pode gastar dinheiro de verdade)

- **Gravar vem desligado** até você pôr *Allow creating* em `yes`.
- **Tudo que o agente cria fica PAUSADO.** Nada gasta até alguém ligar.
- **Ligar é outra chave** (*Allow turning on*), e antes de qualquer ligação o plugin confere todos os orçamentos envolvidos (o anúncio, o conjunto e a campanha) contra o *Highest daily budget*. O que passa do limite é recusado.
- Não dá para gravar orçamento sem o limite definido, e um acima dele é recusado antes de qualquer requisição.
- Toda gravação pede aprovação, a menos que você pré-aprove. Não pré-aprove `meta_ads_set_status`.
- O que volta da Meta (nomes, textos de anúncio, avisos) é escrito por outras pessoas, então chega ao modelo como citação, nunca como instrução.
- Alguns públicos são restritos pela Meta (moradia, emprego, crédito, política). O agente precisa informar a categoria especial; nunca chuta.
