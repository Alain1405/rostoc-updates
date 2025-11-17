import{r as t,j as l}from"./iframe-BXD7fudD.js";import{S as s}from"./Select-Cqc8kr0O.js";import"./preload-helper-JDnY5PGr.js";const R={title:"Rostoc Design System/Components/Select",component:s,parameters:{layout:"centered",docs:{description:{component:`Select (dropdown) components from the Rostoc design system

Select components use the Rostoc color palette and typography styles from Figma.
Labels and options should be in UPPERCASE to match the design system.`}}},tags:["autodocs"]},n={args:{label:"",value:"",options:[],onChange:()=>{}},render:()=>{const[e,a]=t.useState("english");return l.jsx(s,{label:"APPLICATION LANGUAGE",value:e,onChange:a,options:[{value:"english",label:"ENGLISH"},{value:"spanish",label:"ESPAÑOL"},{value:"french",label:"FRANÇAIS"},{value:"german",label:"DEUTSCH"}]})}},o={args:{label:"",value:"",options:[],onChange:()=>{}},render:()=>{const[e,a]=t.useState("dd/mm/yyyy");return l.jsx(s,{label:"DATE FORMAT",value:e,onChange:a,options:[{value:"dd/mm/yyyy",label:"DD/MM/YYYY"},{value:"mm/dd/yyyy",label:"MM/DD/YYYY"},{value:"yyyy-mm-dd",label:"YYYY-MM-DD"}]})}},r={args:{label:"",value:"",options:[],onChange:()=>{}},render:()=>{const[e,a]=t.useState("roaster");return l.jsx(s,{label:"MACHINE TYPE",value:e,onChange:a,options:[{value:"roaster",label:"ROASTER"},{value:"grinder",label:"GRINDER"},{value:"brewer",label:"BREWER"}]})}},u={args:{label:"",value:"",options:[],onChange:()=>{}},render:()=>{const[e,a]=t.useState("english"),[S,A]=t.useState("dd/mm/yyyy");return l.jsxs("div",{className:"grid grid-cols-2 gap-6 w-[600px]",children:[l.jsx(s,{label:"APPLICATION LANGUAGE",value:e,options:[{value:"english",label:"ENGLISH"},{value:"spanish",label:"ESPAÑOL"},{value:"french",label:"FRANÇAIS"}],onChange:a}),l.jsx(s,{label:"DATE FORMAT",value:S,options:[{value:"dd/mm/yyyy",label:"DD/MM/YYYY"},{value:"mm/dd/yyyy",label:"MM/DD/YYYY"},{value:"yyyy-mm-dd",label:"YYYY-MM-DD"}],onChange:A})]})}};var m,d,y;n.parameters={...n.parameters,docs:{...(m=n.parameters)==null?void 0:m.docs,source:{originalSource:`{
  args: {
    label: '',
    value: '',
    options: [],
    onChange: () => {} // Dummy values, not used in render
  },
  render: () => {
    const [value, setValue] = useState('english');
    return <Select label="APPLICATION LANGUAGE" value={value} onChange={setValue} options={[{
      value: 'english',
      label: 'ENGLISH'
    }, {
      value: 'spanish',
      label: 'ESPAÑOL'
    }, {
      value: 'french',
      label: 'FRANÇAIS'
    }, {
      value: 'german',
      label: 'DEUTSCH'
    }]} />;
  }
}`,...(y=(d=n.parameters)==null?void 0:d.docs)==null?void 0:y.source}}};var c,g,i;o.parameters={...o.parameters,docs:{...(c=o.parameters)==null?void 0:c.docs,source:{originalSource:`{
  args: {
    label: '',
    value: '',
    options: [],
    onChange: () => {} // Dummy values, not used in render
  },
  render: () => {
    const [value, setValue] = useState('dd/mm/yyyy');
    return <Select label="DATE FORMAT" value={value} onChange={setValue} options={[{
      value: 'dd/mm/yyyy',
      label: 'DD/MM/YYYY'
    }, {
      value: 'mm/dd/yyyy',
      label: 'MM/DD/YYYY'
    }, {
      value: 'yyyy-mm-dd',
      label: 'YYYY-MM-DD'
    }]} />;
  }
}`,...(i=(g=o.parameters)==null?void 0:g.docs)==null?void 0:i.source}}};var p,v,b;r.parameters={...r.parameters,docs:{...(p=r.parameters)==null?void 0:p.docs,source:{originalSource:`{
  args: {
    label: '',
    value: '',
    options: [],
    onChange: () => {} // Dummy values, not used in render
  },
  render: () => {
    const [value, setValue] = useState('roaster');
    return <Select label="MACHINE TYPE" value={value} onChange={setValue} options={[{
      value: 'roaster',
      label: 'ROASTER'
    }, {
      value: 'grinder',
      label: 'GRINDER'
    }, {
      value: 'brewer',
      label: 'BREWER'
    }]} />;
  }
}`,...(b=(v=r.parameters)==null?void 0:v.docs)==null?void 0:b.source}}};var Y,h,D;u.parameters={...u.parameters,docs:{...(Y=u.parameters)==null?void 0:Y.docs,source:{originalSource:`{
  args: {
    label: '',
    value: '',
    options: [],
    onChange: () => {} // Dummy values, not used in render
  },
  render: () => {
    const [language, setLanguage] = useState('english');
    const [dateFormat, setDateFormat] = useState('dd/mm/yyyy');
    return <div className="grid grid-cols-2 gap-6 w-[600px]">
        <Select label="APPLICATION LANGUAGE" value={language} options={[{
        value: 'english',
        label: 'ENGLISH'
      }, {
        value: 'spanish',
        label: 'ESPAÑOL'
      }, {
        value: 'french',
        label: 'FRANÇAIS'
      }]} onChange={setLanguage} />
        <Select label="DATE FORMAT" value={dateFormat} options={[{
        value: 'dd/mm/yyyy',
        label: 'DD/MM/YYYY'
      }, {
        value: 'mm/dd/yyyy',
        label: 'MM/DD/YYYY'
      }, {
        value: 'yyyy-mm-dd',
        label: 'YYYY-MM-DD'
      }]} onChange={setDateFormat} />
      </div>;
  }
}`,...(D=(h=u.parameters)==null?void 0:h.docs)==null?void 0:D.source}}};const L=["Language","DateFormat","MachineType","Multiple"];export{o as DateFormat,n as Language,r as MachineType,u as Multiple,L as __namedExportsOrder,R as default};
