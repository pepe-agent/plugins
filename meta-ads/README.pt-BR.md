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

## O que você precisa

- Uma conta de **desenvolvedor da Meta** e um **app** (<https://developers.facebook.com>), com o produto **API de Marketing**.
- Uma **conta de anúncio** e uma **Página do Facebook** pela qual os anúncios são publicados (e, opcionalmente, a conta do Instagram ligada).
- Um **token de acesso** com `ads_read` para ler, mais `ads_management` para criar ou alterar. O jeito mais durável é um **Usuário do sistema** no Business Manager, com a conta de anúncio e a Página atribuídas: o token dele não expira. A documentação da Meta descreve os passos; confira com as telas que você vê, pois a Meta as muda com frequência.

## Configure

No painel do Pepe abra **Plugins**, ache **meta-ads** e escolha **Configure**:

| Campo | O que colocar |
|---|---|
| Access token | Escrito como `${META_ADS_ACCESS_TOKEN}`, com o valor real no ambiente do servidor do Pepe |
| Ad account id | A conta padrão (só dígitos). Opcional |
| Facebook Page id | A Página pela qual os anúncios saem. Necessário para criar anúncios |
| Instagram account id | Opcional. Para mostrar o perfil do Instagram nos anúncios |
| Allow creating | `no` (padrão) é só leitura. `yes` deixa o agente criar e alterar, sempre PAUSADO |
| Highest daily budget | O máximo de um orçamento diário, em unidades inteiras como `50`. Obrigatório para gravar qualquer orçamento. Um orçamento total pode ser no máximo isso vezes os dias |
| Allow turning on | `no` (padrão): o agente nunca começa a gastar. `yes` deixa ligar o que tem orçamento dentro do limite |
| Graph API version | Opcional, como `v23.0` |

As mesmas configurações podem vir do ambiente: `META_ADS_ACCESS_TOKEN`, `META_ADS_ACCOUNT_ID`, `META_ADS_MAX_DAILY_BUDGET` e as demais no mesmo estilo.

Depois dê as ferramentas a um agente, começando pela leitura:

```bash
pepe agent tools my-agent --add meta_ads_accounts,meta_ads_campaigns,meta_ads_adsets,meta_ads_ads,meta_ads_insights
```

## Segurança (este plugin pode gastar dinheiro de verdade)

- **Gravar vem desligado** até você pôr *Allow creating* em `yes`.
- **Tudo que o agente cria fica PAUSADO.** Nada gasta até alguém ligar.
- **Ligar é outra chave** (*Allow turning on*), e antes de qualquer ligação o plugin confere todos os orçamentos envolvidos (o anúncio, o conjunto e a campanha) contra o *Highest daily budget*. O que passa do limite é recusado.
- Não dá para gravar orçamento sem o limite definido, e um acima dele é recusado antes de qualquer requisição.
- Toda gravação pede aprovação, a menos que você pré-aprove. Não pré-aprove `meta_ads_set_status`.
- O que volta da Meta (nomes, textos de anúncio, avisos) é escrito por outras pessoas, então chega ao modelo como citação, nunca como instrução.
- Alguns públicos são restritos pela Meta (moradia, emprego, crédito, política). O agente precisa informar a categoria especial; nunca chuta.
