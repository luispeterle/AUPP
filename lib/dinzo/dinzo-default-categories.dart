// GENERATED from the Dinzo category tree (private/samples/categories.json).
// Fork-only: the categories a fresh install starts with, instead of the
// upstream defaults, so a new database already matches Dinzo.
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';

import 'dinzo-sync-service.dart';

class _DefaultCategory {
  final String name;
  final bool income;
  final String? parent;
  final String? colorHex;

  const _DefaultCategory(this.name, this.income, this.parent, this.colorHex);
}

/// Parents come before their children.
const _defaults = <_DefaultCategory>[
  _DefaultCategory('Alimentação', false, null, 'FFA500'),
  _DefaultCategory('Cafeteria', false, 'Alimentação', null),
  _DefaultCategory('Delivery', false, 'Alimentação', null),
  _DefaultCategory('Padaria', false, 'Alimentação', null),
  _DefaultCategory('Restaurante', false, 'Alimentação', null),
  _DefaultCategory('Assinaturas/Serviços', false, null, '5E8CBF'),
  _DefaultCategory('Aplicativos', false, 'Assinaturas/Serviços', null),
  _DefaultCategory('Jogos', false, 'Assinaturas/Serviços', null),
  _DefaultCategory('Streamings', false, 'Assinaturas/Serviços', null),
  _DefaultCategory('Telefone/Celular', false, 'Assinaturas/Serviços', null),
  _DefaultCategory('Televisão', false, 'Assinaturas/Serviços', null),
  _DefaultCategory('Compras', false, null, '#8E24AA'),
  _DefaultCategory('Cuidado Pessoal', false, null, 'B0E0E6'),
  _DefaultCategory('Cabeleireiro/Barbeiro', false, 'Cuidado Pessoal', null),
  _DefaultCategory('Higiene Pessoal', false, 'Cuidado Pessoal', null),
  _DefaultCategory('Manicure', false, 'Cuidado Pessoal', null),
  _DefaultCategory('Maquiagem', false, 'Cuidado Pessoal', null),
  _DefaultCategory('Dívidas/Empréstimos', false, null, 'CC0000'),
  _DefaultCategory('Cartão de Crédito', false, 'Dívidas/Empréstimos', null),
  _DefaultCategory('Cheque Especial', false, 'Dívidas/Empréstimos', null),
  _DefaultCategory('Consórcio', false, 'Dívidas/Empréstimos', null),
  _DefaultCategory('Empréstimo', false, 'Dívidas/Empréstimos', null),
  _DefaultCategory('Empréstimo Consignado', false, 'Dívidas/Empréstimos', null),
  _DefaultCategory('Encargos', false, 'Dívidas/Empréstimos', null),
  _DefaultCategory('Financiamento', false, 'Dívidas/Empréstimos', null),
  _DefaultCategory('Renegociação', false, 'Dívidas/Empréstimos', null),
  _DefaultCategory('Educação', false, null, '4A90E2'),
  _DefaultCategory('Cursos', false, 'Educação', null),
  _DefaultCategory('Escola', false, 'Educação', null),
  _DefaultCategory('Faculdade', false, 'Educação', null),
  _DefaultCategory('Materiais e Livros', false, 'Educação', null),
  _DefaultCategory('Impostos/Taxas', false, null, '6D7B8D'),
  _DefaultCategory('Anuidade Cartão', false, 'Impostos/Taxas', null),
  _DefaultCategory('Imposto de Renda', false, 'Impostos/Taxas', null),
  _DefaultCategory('Tarifa Bancária', false, 'Impostos/Taxas', null),
  _DefaultCategory('Tributos', false, 'Impostos/Taxas', null),
  _DefaultCategory('Lazer/Hobbies', false, null, 'FFA500'),
  _DefaultCategory('Bares', false, 'Lazer/Hobbies', null),
  _DefaultCategory('Cinema', false, 'Lazer/Hobbies', null),
  _DefaultCategory('Esportes', false, 'Lazer/Hobbies', null),
  _DefaultCategory('Parques', false, 'Lazer/Hobbies', null),
  _DefaultCategory('Shows e Eventos', false, 'Lazer/Hobbies', null),
  _DefaultCategory('Teatro', false, 'Lazer/Hobbies', null),
  _DefaultCategory('Moradia', false, null, '8B4513'),
  _DefaultCategory('Aluguel/Prestação', false, 'Moradia', null),
  _DefaultCategory('Condomínio', false, 'Moradia', null),
  _DefaultCategory('Diarista', false, 'Moradia', null),
  _DefaultCategory('Eletrodomésticos', false, 'Moradia', null),
  _DefaultCategory('Gás', false, 'Moradia', null),
  _DefaultCategory('IPTU', false, 'Moradia', null),
  _DefaultCategory('Internet', false, 'Moradia', null),
  _DefaultCategory('Luz', false, 'Moradia', null),
  _DefaultCategory('Móveis', false, 'Moradia', null),
  _DefaultCategory('Reformas', false, 'Moradia', null),
  _DefaultCategory('Seguro Residencial', false, 'Moradia', null),
  _DefaultCategory('Água', false, 'Moradia', null),
  _DefaultCategory('Outros', false, null, '78909C'),
  _DefaultCategory('Presentes/Doações', false, 'Outros', null),
  _DefaultCategory('Transferência', false, 'Outros', null),
  _DefaultCategory('Outros', true, null, '78909C'),
  _DefaultCategory('Presentes/Doações', true, 'Outros', null),
  _DefaultCategory('Transferência', true, 'Outros', null),
  _DefaultCategory('Pets', false, null, 'F0D2A7'),
  _DefaultCategory('Acessórios Pet', false, 'Pets', null),
  _DefaultCategory('Alimentação Pet', false, 'Pets', null),
  _DefaultCategory('Banho/Tosa', false, 'Pets', null),
  _DefaultCategory('Medicamentos', false, 'Pets', null),
  _DefaultCategory('Veterinário', false, 'Pets', null),
  _DefaultCategory('Salário', true, null, '00A300'),
  _DefaultCategory('13° Salário', true, 'Salário', null),
  _DefaultCategory('Aposentadoria', true, 'Salário', null),
  _DefaultCategory('Comissão', true, 'Salário', null),
  _DefaultCategory('Férias', true, 'Salário', null),
  _DefaultCategory('Hora extra', true, 'Salário', null),
  _DefaultCategory('Trabalho', true, 'Salário', null),
  _DefaultCategory('Vale alimentação', true, 'Salário', null),
  _DefaultCategory('Saúde', false, null, '2ECC71'),
  _DefaultCategory('Academia', false, 'Saúde', null),
  _DefaultCategory('Consultas', false, 'Saúde', null),
  _DefaultCategory('Dentista', false, 'Saúde', null),
  _DefaultCategory('Exames', false, 'Saúde', null),
  _DefaultCategory('Farmácia', false, 'Saúde', null),
  _DefaultCategory('Plano Odontológico', false, 'Saúde', null),
  _DefaultCategory('Plano de Saúde', false, 'Saúde', null),
  _DefaultCategory('Seguro de Vida', false, 'Saúde', null),
  _DefaultCategory('Supermercado', false, null, '66BB6A'),
  _DefaultCategory('Transporte', false, null, '4682B4'),
  _DefaultCategory('Combustível', false, 'Transporte', null),
  _DefaultCategory('Estacionamento', false, 'Transporte', null),
  _DefaultCategory('IPVA', false, 'Transporte', null),
  _DefaultCategory('Lavação', false, 'Transporte', null),
  _DefaultCategory('Licenciamento', false, 'Transporte', null),
  _DefaultCategory('Manutenção', false, 'Transporte', null),
  _DefaultCategory('Multa', false, 'Transporte', null),
  _DefaultCategory('Pedágio', false, 'Transporte', null),
  _DefaultCategory('Prestação', false, 'Transporte', null),
  _DefaultCategory('Seguro do Carro', false, 'Transporte', null),
  _DefaultCategory('Taxi/Uber', false, 'Transporte', null),
  _DefaultCategory('Transporte Público', false, 'Transporte', null),
  _DefaultCategory('Vestuário', false, null, 'D2B48C'),
  _DefaultCategory('Acessórios', false, 'Vestuário', null),
  _DefaultCategory('Calçados', false, 'Vestuário', null),
  _DefaultCategory('Roupas', false, 'Vestuário', null),
  _DefaultCategory('Viagens', false, null, '5DADE2'),
  _DefaultCategory('Hotel', false, 'Viagens', null),
  _DefaultCategory('Passagem', false, 'Viagens', null),
  _DefaultCategory('Passeio', false, 'Viagens', null),
  _DefaultCategory('Sem categoria', false, null, '#607D8B'),
  _DefaultCategory('Sem categoria', true, null, '#607D8B'),
  _DefaultCategory('Rendimentos', true, null, '#607D8B'),
  _DefaultCategory('Ajuste de saldo', false, null, '#607D8B'),
];

/// The Dinzo tree as AUPP categories: subcategories linked to their
/// parent, shades of the parent's colour and their own icons, exactly as the
/// sync would create them.
List<Category> dinzoDefaultCategories() {
  final created = <String, Category>{};
  return [
    for (final d in _defaults)
      () {
        final type = d.income ? CategoryType.income : CategoryType.expense;
        final category = DinzoSyncService.categoryFromDinzo(
          d.name,
          type,
          parent: d.parent == null
              ? null
              : created['${d.parent}|${type.index}'],
          colorHex: d.colorHex,
        );
        created['${d.name}|${type.index}'] = category;
        return category;
      }(),
  ];
}
